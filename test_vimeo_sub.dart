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
  final masterM3u8Url = hlsMatch?.group(1);
  print('Master M3U8 URL: $masterM3u8Url');

  if (masterM3u8Url != null) {
    final subRes = await dio.get<String>(
      masterM3u8Url,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://vimeo.com/',
        },
      ),
    );

    print('Sub M3U8 content:');
    print(subRes.data);
  }
}
