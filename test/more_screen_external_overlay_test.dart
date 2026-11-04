import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/more_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async =>
      BackendSettings.fromInput(baseUrl: 'https://example.test', apiKey: '');

  @override
  Future<void> save(BackendSettings value) async {}
}

class _FakeResolver extends Fake implements BackendMediaResolver {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vidsave/external_app_download_overlay');

  late bool canDrawOverlays;
  late bool hasUsageAccess;
  late bool enabled;
  late List<String> methods;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    canDrawOverlays = false;
    hasUsageAccess = false;
    enabled = false;
    methods = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          switch (call.method) {
            case 'getStatus':
              return {
                'canDrawOverlays': canDrawOverlays,
                'hasUsageAccess': hasUsageAccess,
                'enabled': enabled,
              };
            case 'start':
              enabled = true;
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('enables immediately on the first permission grant', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final store = _FakeSettingsStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoreScreen(store: store, resolver: _FakeResolver()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('external_app_download_overlay_switch'),
      );
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(
        methods.where((method) => method == 'requestNextPermission').length,
        1,
      );

      // Kullanıcı ilk izni (canDrawOverlays) onaylayıp uygulamaya geri döndüğünde
      // ikinci bir izin istemeden doğrudan etkinleşmelidir.
      canDrawOverlays = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        methods.where((method) => method == 'requestNextPermission').length,
        1,
      );
      expect(methods, contains('start'));
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
