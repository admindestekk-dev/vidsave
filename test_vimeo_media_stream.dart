import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final masterRes = await dio.get<String>(
    'https://player.vimeo.com/video/76979871',
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = masterRes.data ?? '';
  final hlsMatch = RegExp(
    r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"',
  ).firstMatch(html);
  var rawUrl = hlsMatch?.group(1);
  if (rawUrl != null) {
    rawUrl = rawUrl
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003d', '=');
    final masterUri = Uri.parse(rawUrl);

    final subRes = await dio.get<String>(
      rawUrl,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://player.vimeo.com/',
        },
      ),
    );

    final lines = (subRes.data ?? '').split('\n');
    print('Total lines in master: ${lines.length}');
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      if (l.startsWith('#EXT-X-STREAM-INF')) {
        print('Stream inf: $l');
        print('  Next line (URI): ${lines[i + 1].trim()}');
        final resolvedSub = masterUri.resolve(lines[i + 1].trim());
        print('  Resolved sub URI: $resolvedSub');

        // Let's inspect this sub playlist!
        final mediaPlaylistRes = await dio.get<String>(
          resolvedSub.toString(),
          options: Options(
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://player.vimeo.com/',
            },
          ),
        );
        print('  Media Playlist Status: ${mediaPlaylistRes.statusCode}');
        print('  Media Playlist First 300 chars:');
        print(mediaPlaylistRes.data?.substring(0, 300));
        break;
      }
    }
  }
}
