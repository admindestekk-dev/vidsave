import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

void main() {
  test('Vimeo test on live url', () async {
    final scraper = UniversalScraper();
    try {
      final res = await scraper.resolve(
        Uri.parse('https://vimeo.com/76979871'),
        DownloadKind.video,
      );
      debugPrint('RESOLVED SUCCESS!');
      debugPrint('URL: ${res.url}');
      debugPrint('Filename: ${res.fileName}');
      debugPrint('byteStreamProvider: ${res.byteStreamProvider != null}');
      expect(res.url.toString().isNotEmpty, isTrue);
      expect(res.fileName.endsWith('.mp4'), isTrue);
      if (res.byteStreamProvider != null) {
        final stream = res.byteStreamProvider!();
        final firstChunk = await stream.first;
        debugPrint('First chunk bytes: ${firstChunk.length}');
        expect(firstChunk.length, greaterThan(0));
      }
    } finally {
      scraper.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
