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
  // Check CDNs in playerConfig
  final cdnsMatch = RegExp(
    r'"cdns":\s*(\{.*?\})\s*,\s*"default_cdn"',
    dotAll: true,
  ).firstMatch(html);
  print(cdnsMatch?.group(1));
}
