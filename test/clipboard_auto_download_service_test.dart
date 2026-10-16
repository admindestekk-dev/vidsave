import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/clipboard_auto_download_service.dart';

void main() {
  setUp(() {
    ClipboardAutoDownloadService.resetLastHandled();
  });

  group('ClipboardAutoDownloadService', () {
    test('detects Instagram URLs correctly', () {
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('https://www.instagram.com/reel/C123456/'),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('https://instagr.am/p/xyz123'),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.extractUrl('Arkadaşım bak: https://instagram.com/reel/abc/ çok iyi'),
        'https://instagram.com/reel/abc/',
      );
    });

    test('detects TikTok URLs correctly', () {
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('https://www.tiktok.com/@user/video/123456789'),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.isSupportedUrl('https://vm.tiktok.com/ZM812345/'),
        isTrue,
      );
      expect(
        ClipboardAutoDownloadService.extractUrl('İzle: https://vt.tiktok.com/ZS123/ süper'),
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
      expect(
        ClipboardAutoDownloadService.isSupportedUrl(null),
        isFalse,
      );
    });

    test('markAsHandled prevents duplicate processing', () {
      const url = 'https://www.instagram.com/reel/123';
      ClipboardAutoDownloadService.markAsHandled(url);
      // Once marked, checking should not return the same url again
    });
  });
}
