import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/more_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async => const BackendSettings(
    baseUrl: 'https://example.test',
    apiKey: 'test-key',
  );

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _FakeResolver extends Fake implements BackendMediaResolver {}

class _MemoryTokenStore implements AuthTokenStore {
  String? token;
  String? userId;

  @override
  Future<void> clearToken() async {
    token = null;
    userId = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> saveUserId(String value) async => userId = value;
}

Widget _buildMoreScreenApp({required AuthService authService}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    home: Scaffold(
      body: MoreScreen(
        store: _FakeSettingsStore(),
        resolver: _FakeResolver(),
        authService: authService,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Support & Contact section shows dynamic User ID, copies to clipboard on tap with SnackBar, and renders email tile',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tokenStore = _MemoryTokenStore();
      await tokenStore.saveToken('jwt-session-abc');
      await tokenStore.saveUserId('user-pro-999-uuid');

      final authService = AuthService(
        settingsStore: _FakeSettingsStore(),
        tokenStore: tokenStore,
      );

      // Intercept system clipboard
      String? copiedClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final args = methodCall.arguments as Map<dynamic, dynamic>;
            copiedClipboardText = args['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(_buildMoreScreenApp(authService: authService));
      await tester.pumpAndSettle();

      // 1. Destek Kodu (User ID) başlığını ve kullanıcının ID'sini doğrula
      final supportCodeTitle = find.text('Destek Kodu (User ID)');
      expect(supportCodeTitle, findsOneWidget);
      await tester.ensureVisible(supportCodeTitle);

      expect(find.text('user-pro-999-uuid'), findsOneWidget);

      // 2. Destek Kodu satırına tıkla ve panoya kopyalama ile SnackBar'ı doğrula
      await tester.tap(supportCodeTitle);
      await tester.pumpAndSettle();

      expect(copiedClipboardText, 'user-pro-999-uuid');
      expect(find.text('Destek kodu panoya kopyalandı!'), findsOneWidget);

      // 3. E-posta iletişim butonunu (ListTile) doğrula
      final emailTileTitle = find.text('Bize Ulaşın / Destek Alın');
      expect(emailTileTitle, findsOneWidget);
      expect(find.text('admindestekk@gmail.com'), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
    },
  );
}
