import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/external_app_download_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vidsave/external_app_download_overlay');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads overlay and usage access status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getStatus');
          return {
            'canDrawOverlays': true,
            'hasUsageAccess': true,
            'enabled': true,
          };
        });

    final status = await ExternalAppDownloadOverlay.getStatus();

    expect(status.canDrawOverlays, isTrue);
    expect(status.hasUsageAccess, isTrue);
    expect(status.enabled, isTrue);
    expect(status.hasRequiredPermissions, isTrue);
  });

  test('calls native permission, start, and stop methods', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return null;
        });

    await ExternalAppDownloadOverlay.requestNextPermission();
    await ExternalAppDownloadOverlay.start();
    await ExternalAppDownloadOverlay.stop();

    expect(methods, ['requestNextPermission', 'start', 'stop']);
  });

  test('reads pending download url from overlay action', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getPendingDownloadUrl') {
            return 'https://www.instagram.com/reel/Cx12345/';
          }
          return null;
        });

    final url = await ExternalAppDownloadOverlay.getPendingDownloadUrl();
    expect(url, 'https://www.instagram.com/reel/Cx12345/');
  });
}
