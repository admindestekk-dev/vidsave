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
  // Check for progressive, mp4, streams
  print('HTML length: ${html.length}');

  final matches = RegExp(r'"url":\s*"([^"]+)"').allMatches(html);
  for (final m in matches) {
    final u = m.group(1)!.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');
    if (u.contains('progressive') ||
        u.contains('.mp4') ||
        u.contains('vimeocdn')) {
      print('URL: $u');
    }
  }

  // Look for config url or player config
  final configMatch =
      RegExp(
        r'window\.playerConfig\s*=\s*(\{.*?\});',
        dotAll: true,
      ).firstMatch(html) ??
      RegExp(r'"config_url":\s*"([^"]+)"').firstMatch(html);
  print('Config found: ${configMatch != null}');
}
