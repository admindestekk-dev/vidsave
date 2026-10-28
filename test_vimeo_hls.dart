// ignore_for_file: avoid_print

import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://vimeo.com/76979871';
  print('Resolving Vimeo: $vimeoUrl');
  final videoId = RegExp(r'vimeo\.com/(?:video/)?(\d+)').firstMatch(vimeoUrl)?.group(1) ?? '76979871';
  final res = await dio.get<String>(
    'https://player.vimeo.com/video/$videoId',
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = res.data ?? '';
  final hlsMatch = RegExp(
    r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"',
  ).firstMatch(html);
  final hlsUrl = hlsMatch?.group(1);
  print('HLS URL: $hlsUrl');

  if (hlsUrl != null) {
    final m3u8Res = await dio.get<String>(
      hlsUrl,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://vimeo.com/',
        },
      ),
    );
    print('Master M3U8 content preview:');
    print(m3u8Res.data?.substring(0, 500));
  }
}