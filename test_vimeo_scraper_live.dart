import 'package:dio/dio.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

void main() async {
  final scraper = UniversalScraper();
  print('Resolving Vimeo with UniversalScraper...');
  try {
    final res = await scraper.resolve(
      Uri.parse('https://vimeo.com/76979871'),
      DownloadKind.video,
    );
    print('RESOLVED SUCCESS!');
    print('URL: ${res.url}');
    print('Filename: ${res.fileName}');
    print('byteStreamProvider: ${res.byteStreamProvider != null}');
    if (res.byteStreamProvider != null) {
      print('Testing first byteStream chunk...');
      final stream = res.byteStreamProvider!();
      final firstChunk = await stream.first;
      print('First chunk bytes: ${firstChunk.length}');
      if (firstChunk.sublist(4, 8).map((b) => String.fromCharCode(b)).join() ==
          'ftyp') {
        print('VERIFIED MP4 HEADER IN FIRST CHUNK!');
      }
    }
  } catch (e, stack) {
    print('ERROR: $e\n$stack');
  } finally {
    scraper.dispose();
  }
}
