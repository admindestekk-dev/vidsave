import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://vimeo.com/76979871';
  print('Testing Vimeo URL: $vimeoUrl');

  final vimeoMatch = RegExp(r'vimeo\.com/(?:video/)?(\d+)')
      .firstMatch(vimeoUrl);
  final videoId = vimeoMatch?.group(1);
  print('Video ID: $videoId');

  final targetUrls = [
    if (videoId != null) 'https://player.vimeo.com/video/$videoId/config',
    if (videoId != null) 'https://player.vimeo.com/video/$videoId',
    vimeoUrl,
  ];

  for (final target in targetUrls) {
    print('\nTrying target: $target');
    try {
      final res = await dio.get<String>(
        target,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Referer': 'https://vimeo.com/',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      print('  Status: ${res.statusCode}, Len: ${res.data?.length}');
      final text = res.data ?? '';

      // Check keywords
      final progressive = RegExp(
        r'"url":\s*"(https://player\.vimeo\.com/progressive_redirect/[^"]+)"',
      ).allMatches(text);
      print('  progressive_redirect matches: ${progressive.length}');
      for (final m in progressive) {
        print('    progressive URL: ${m.group(1)}');
      }

      final akamai = RegExp(
        r'"url":\s*"(https://[^"]*(?:akamaized|vimeocdn|fastly)[^"]*\.mp4[^"]*)"',
      ).allMatches(text);
      print('  akamai/vimeocdn mp4 matches: ${akamai.length}');
      for (final m in akamai) {
        print('    akamai URL: ${m.group(1)}');
      }

      final hls = RegExp(r'"url":\s*"(https://[^"]*\.m3u8[^"]*)"')
          .allMatches(text);
      print('  m3u8 matches: ${hls.length}');
      for (final m in hls) {
        print('    m3u8 URL: ${m.group(1)}');
      }
    } catch (e) {
      print('  Error: $e');
    }
  }
}
