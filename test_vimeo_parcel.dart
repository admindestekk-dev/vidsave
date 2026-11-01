import 'dart:convert';

import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://player.vimeo.com/video/76979871';

  final res = await dio.get<String>(
    vimeoUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = res.data ?? '';
  final startIdx = html.indexOf('window.playerConfig = {');
  final jsonStart = startIdx + 'window.playerConfig = '.length;
  final endIdx = html.indexOf('</script>', jsonStart);
  var jsonStr = html
      .substring(jsonStart, endIdx != -1 ? endIdx : html.length)
      .trim();
  if (jsonStr.endsWith(';'))
    jsonStr = jsonStr.substring(0, jsonStr.length - 1).trim();

  final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
  final request = jsonMap['request'] as Map<String, dynamic>?;
  final files = request?['files'] as Map<String, dynamic>?;
  final cdns = files?['hls']?['cdns'] as Map<String, dynamic>?;
  final defaultCdn =
      files?['hls']?['default_cdn']?.toString() ?? cdns?.keys.first;
  final cdnObj = cdns?[defaultCdn] ?? cdns?.values.first;
  var hlsUrl = cdnObj['url']?.toString();

  print('Original HLS URL: $hlsUrl');

  // Let's test the parcel replacement mentioned in the forum!
  // replace from '/v2/' up to video/ or parcel
  final parcelUrl = hlsUrl!.replaceAll(
    RegExp(r'/v2/.*'),
    '/parcel/video/5850de2a.mp4',
  );
  print('Parcel URL: $parcelUrl');

  try {
    final pRes = await dio.head(
      parcelUrl,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://player.vimeo.com/',
        },
      ),
    );
    print(
      'PARCEL SUCCESS! Status: ${pRes.statusCode}, Content-Length: ${pRes.headers.value('content-length')}',
    );
  } catch (e) {
    print('Parcel failed: $e');
  }
}
