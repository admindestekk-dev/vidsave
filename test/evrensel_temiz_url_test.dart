import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/media_downloader.dart';

void main() {
  group('evrenselTemizUrl shield tests', () {
    test('cleans raw quotes around URLs', () {
      expect(
        evrenselTemizUrl('"https://example.com/video.mp4"'),
        'https://example.com/video.mp4',
      );
      expect(
        evrenselTemizUrl("'https://example.com/video.mp4'"),
        'https://example.com/video.mp4',
      );
    });

    test('replaces JSON escaped slashes and HTML entities', () {
      const raw = r'https:\/\/v16-webapp-prime.tiktok.com\/video\/123?param=1&amp;val=2';
      expect(
        evrenselTemizUrl(raw),
        'https://v16-webapp-prime.tiktok.com/video/123?param=1&val=2',
      );
    });

    test(r'replaces unicode \u002F and \u0026 escape sequences', () {
      const raw = r'https:\u002F\u002Fv16-webapp-prime.tiktok.com\u002Fvideo\u002F123';
      expect(
        evrenselTemizUrl(raw),
        'https://v16-webapp-prime.tiktok.com/video/123',
      );
    });

    test('recovers from "u002F" literal text residue and prevents "No host specified" error', () {
      // The exact error string mentioned by user:
      // "https://u002F/u002Fv16-webapp-prime.tiktokcdn.com/video.mp4"
      const raw = 'https://u002F/u002Fv16-webapp-prime.tiktokcdn.com/video.mp4';
      final clean = evrenselTemizUrl(raw);
      expect(clean, 'https://v16-webapp-prime.tiktokcdn.com/video.mp4');

      // Verify that Uri.parse succeeds and recognizes the valid host
      final uri = Uri.parse(clean);
      expect(uri.host, 'v16-webapp-prime.tiktokcdn.com');
      expect(uri.path, '/video.mp4');
    });

    test('fixes triple-slash https:/// and single-slash https:/ protocol anomalies', () {
      expect(
        evrenselTemizUrl('https:///v16-webapp-prime.tiktokcdn.com/video.mp4'),
        'https://v16-webapp-prime.tiktokcdn.com/video.mp4',
      );
      expect(
        evrenselTemizUrl('https:/v16-webapp-prime.tiktokcdn.com/video.mp4'),
        'https://v16-webapp-prime.tiktokcdn.com/video.mp4',
      );
      expect(
        evrenselTemizUrl('//v16-webapp-prime.tiktokcdn.com/video.mp4'),
        'https://v16-webapp-prime.tiktokcdn.com/video.mp4',
      );
    });

    test('preserves valid http:// and https:// URLs without modification', () {
      expect(
        evrenselTemizUrl('http://example.com/audio.mp3'),
        'http://example.com/audio.mp3',
      );
      expect(
        evrenselTemizUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });
  });
}
