import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/app_dio.dart';

void main() {
  group('AppDio Global Client & Cookie Management Tests', () {
    test('AppDio instance has legal browser headers configured', () {
      final dio = AppDio.instance;
      final headers = dio.options.headers;

      expect(
        headers['User-Agent'],
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      );
      expect(
        headers['Accept'],
        'video/webm,video/mp4,video/*,audio/*,*/*',
      );
      expect(
        headers['Accept-Language'],
        'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      expect(headers['Referer'], 'https://youtube.com');
      expect(headers['Origin'], 'https://youtube.com');
      expect(headers['Sec-Fetch-Mode'], 'cors');
      expect(headers['Sec-Fetch-Site'], 'cross-site');
    });

    test('InMemoryCookieJar captures, stores and retrieves cookies by domain', () {
      final jar = InMemoryCookieJar();
      final uri = Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');

      jar.saveFromResponse(uri, [
        'VISITOR_INFO1_LIVE=abc1234; Path=/; Domain=.youtube.com; Secure; HttpOnly',
        'YSC=xyz5678; Path=/; Domain=.youtube.com',
      ]);

      final cookieHeader = jar.getCookieHeader(uri);
      expect(cookieHeader, isNotNull);
      expect(cookieHeader, contains('VISITOR_INFO1_LIVE=abc1234'));
      expect(cookieHeader, contains('YSC=xyz5678'));

      // Check sub-domain match
      final cdnUri = Uri.parse('https://rr1---sn-4g5edn7e.googlevideo.com/videoplayback');
      jar.saveFromResponse(cdnUri, ['GPS=1; Path=/; Domain=.googlevideo.com']);
      expect(jar.getCookieHeader(cdnUri), contains('GPS=1'));
    });

    test('CookieAndMaskingInterceptor dynamically impersonates platform and injects cookies', () async {
      final jar = InMemoryCookieJar();
      final dio = AppDio.createClient(jar: jar);

      // Pre-populate cookie for tiktok
      jar.saveFromResponse(Uri.parse('https://www.tiktok.com/'), [
        'tt_webid_v2=723456789; Path=/; Domain=.tiktok.com',
      ]);

      // Use a custom test interceptor to capture outgoing request options without doing network I/O
      RequestOptions? capturedOptions;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedOptions = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: 'ok',
              ),
            );
          },
        ),
      );

      // 1. YouTube request
      await dio.get<dynamic>('https://rr1---sn-4g5edn7e.googlevideo.com/videoplayback');
      expect(capturedOptions?.headers['Referer'], 'https://youtube.com');
      expect(capturedOptions?.headers['Origin'], 'https://youtube.com');

      // 2. TikTok request
      await dio.get<dynamic>('https://v16-webapp-prime.tiktokcdn.com/video/mp4');
      expect(capturedOptions?.headers['Referer'], 'https://www.tiktok.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.tiktok.com');
      expect(capturedOptions?.headers['Cookie'], contains('tt_webid_v2=723456789'));

      // 3. Instagram request
      await dio.get<dynamic>('https://scontent.cdninstagram.com/v/t50.2886-16/test.mp4');
      expect(capturedOptions?.headers['Referer'], 'https://www.instagram.com/');
      expect(capturedOptions?.headers['Origin'], 'https://www.instagram.com');
    });
  });
}
