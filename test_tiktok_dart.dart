import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  const testUrls = [
    'https://www.tiktok.com/@scout2015/video/6718335390845095173',
  ];

  for (final url in testUrls) {
    print('Testing TikTok resolution for: $url');
    String? videoUrl;
    String? title;

    // Bridge 1: TikWM
    try {
      print('  Trying TikWM...');
      final tikwmRes = await dio.post<Map<String, dynamic>>(
        'https://www.tikwm.com/api/',
        data: {'url': url, 'count': 12, 'cursor': 0, 'web': 1},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'User-Agent': 'Mozilla/5.0'},
          validateStatus: (s) => s != null && s < 400,
        ),
      );

      final tikData = tikwmRes.data?['data'];
      if (tikData != null && tikData is Map) {
        final playUrl = tikData['play'] ?? tikData['wmplay'];
        if (playUrl != null) {
          videoUrl = playUrl.toString().startsWith('http')
              ? playUrl.toString()
              : 'https://www.tikwm.com$playUrl';
          title = tikData['title'] as String? ?? 'tiktok_video';
          print('  TikWM Success! videoUrl: $videoUrl');
        }
      }
    } catch (e) {
      print('  TikWM error: $e');
    }

    // Bridge 2: TikMate (if TikWM didn't get video)
    if (videoUrl == null) {
      try {
        print('  Trying TikMate...');
        final tikmateRes = await dio.post<Map<String, dynamic>>(
          'https://api.tikmate.app/api/lookup',
          data: {'url': url},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'User-Agent': 'Mozilla/5.0'},
            validateStatus: (s) => s != null && s < 400,
          ),
        );
        final token = tikmateRes.data?['token'];
        final id = tikmateRes.data?['id'];
        if (token != null && id != null) {
          videoUrl = 'https://tikmate.app/download/$token/$id.mp4?hd=1';
          title = tikmateRes.data?['author_name'] as String? ?? 'tiktok_video';
          print('  TikMate Success! videoUrl: $videoUrl');
        }
      } catch (e) {
        print('  TikMate error: $e');
      }
    }

    // Test downloading stream of resolved videoUrl
    if (videoUrl != null) {
      try {
        final streamRes = await dio.get<ResponseBody>(
          videoUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
              'Referer': 'https://www.tiktok.com/',
            },
          ),
        );
        print(
          '  STREAM SUCCESS! Status: ${streamRes.statusCode}, Content-Length: ${streamRes.headers.value('content-length')}, Content-Type: ${streamRes.headers.value('content-type')}',
        );
      } catch (e) {
        print('  Stream download failed: $e');
      }
    } else {
      print('  FAILED TO RESOLVE TIKTOK');
    }
  }
}
