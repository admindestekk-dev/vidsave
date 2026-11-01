import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(followRedirects: true, maxRedirects: 8));

  const videoUrl = 'https://eeinstagram.com/videos/DOkmaemDPbU/1';

  print('Testing HEAD...');
  final headRes = await dio.head(
    videoUrl,
    options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Referer': 'https://www.instagram.com/',
      },
    ),
  );
  print('HEAD status: ${headRes.statusCode}');
  print('HEAD headers content-type: ${headRes.headers.value('content-type')}');
  print(
    'HEAD headers content-length: ${headRes.headers.value('content-length')}',
  );
}
