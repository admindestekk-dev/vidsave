import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/clipboard_auto_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var clipboardText = '';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClipboardAutoDownloadService.resetLastHandled();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });
  });

  group('ClipboardAutoDownloadService', () {
    test('detects Instagram URLs correctly', () {
      expect(
        ClipboardAutoDownloadService.isSupportedUrl(
          'https://www.instagram.com/reel/C123456/',
        ),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.isSupportedUrl(
          'https://instagr.am/p/xyz123',
        ),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.extractUrl(
          'Arkadaşım bak: https://instagram.com/reel/abc/ çok iyi',
        ),
        'https://instagram.com/reel/abc/',
      );
    });

    test('detects TikTok URLs correctly', () {
      expect(
        ClipboardAutoDownloadService.isSupportedUrl(
          'https://www.tiktok.com/@user/video/123456789',
        ),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.isSupportedUrl(
          'https://vm.tiktok.com/ZM812345/',
        ),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.extractUrl(
          'İzle: https://vt.tiktok.com/ZS123/ süper',
        ),
        'https://vt.tiktok.com/ZS123/',
      );
    });

    test('ignores unsupported URLs and normal text', () {
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('https://google.com'),
        isFalse,
      );
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('Merhaba nasılsın?'),
        isFalse,
      );
      expect(ClipboardAutoDownloadService.isSupportedUrl(null), isFalse);
    });

    test('does not re-detect the same URL after app memory is reset', () async {
      const url = 'https://www.instagram.com/reel/123';
      clipboardText = url;

      expect(
        await ClipboardAutoDownloadService.checkClipboardForDownloadUrl(),
        url,
      );
      final preferences = await SharedPreferences.getInstance();
      final savedFingerprint = preferences.getString(
        'clipboard_auto_download_last_handled_url',
      );
      expect(savedFingerprint, isNotNull);
      expect(savedFingerprint, isNot(url));
      expect(savedFingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));

      ClipboardAutoDownloadService.resetLastHandled();

      expect(
        await ClipboardAutoDownloadService.checkClipboardForDownloadUrl(),
        isNull,
      );
    });

    test('detects a new URL after a previously handled URL', () async {
      clipboardText = 'https://www.instagram.com/reel/123';
      await ClipboardAutoDownloadService.checkClipboardForDownloadUrl();

      clipboardText = 'https://www.tiktok.com/@user/video/456';

      expect(
        await ClipboardAutoDownloadService.checkClipboardForDownloadUrl(),
        'https://www.tiktok.com/@user/video/456',
      );
    });
  });
}
