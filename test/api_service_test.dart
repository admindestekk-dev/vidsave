import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/api_service.dart';
import 'package:vid_downloader_app/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ApiService Tests', () {
    test('analyze resolves video stream successfully with clean headers and download_url', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path.endsWith('/api/analyze'), isTrue);
            expect(options.method, 'POST');
            expect(options.data['url'], 'https://vimeo.com/123456');
            expect(options.data['type'], 'video');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'download_url':
                      'https://player.vimeo.com/progressive_redirect/123.mp4',
                  'title': 'Test Vimeo Video',
                  'filename': 'Test Vimeo Video.mp4',
                  'duration': 120,
                  'type': 'video',
                  'ext': 'mp4',
                },
              ),
            );
          },
        ),
      );

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8787',
        dioClient: dio,
      );
      final result = await apiService.analyze(
        url: 'https://vimeo.com/123456',
        type: 'video',
      );

      expect(
        result.downloadUrl,
        'https://player.vimeo.com/progressive_redirect/123.mp4',
      );
      expect(result.title, 'Test Vimeo Video');
      expect(result.filename, 'Test Vimeo Video.mp4');
      expect(result.duration, 120);
      expect(result.type, 'video');
      expect(result.ext, 'mp4');
    });

    test('analyze resolves mp3 audio stream successfully', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.data['type'], 'mp3');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'status': 'success',
                  'download_url': 'https://example.com/audio_stream.m4a',
                  'title': 'Test Audio Track',
                  'filename': 'Test Audio Track.mp3',
                  'duration': 210,
                  'type': 'mp3',
                  'ext': 'mp3',
                },
              ),
            );
          },
        ),
      );

      final apiService = ApiService(
        baseUrl: 'http://127.0.0.1:8787',
        dioClient: dio,
      );
      final result = await apiService.analyze(
        url: 'https://youtube.com/watch?v=mock',
        type: 'mp3',
      );

      expect(result.downloadUrl, 'https://example.com/audio_stream.m4a');
      expect(result.title, 'Test Audio Track');
      expect(result.type, 'mp3');
    });

    test(
      'analyze throws ApiException when server returns error status',
      () async {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 422,
                  data: {
                    'status': 'error',
                    'error': {
                      'code': 'stream_not_found',
                      'message': 'Medya akışı bulunamadı.',
                    },
                  },
                ),
              );
            },
          ),
        );

        final apiService = ApiService(
          baseUrl: 'http://127.0.0.1:8787',
          dioClient: dio,
        );
        expect(
          () => apiService.analyze(url: 'https://invalid.com/video'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Medya akışı bulunamadı.'),
            ),
          ),
        );
      },
    );

    test('default ApiService options use 30 seconds connect and receive timeouts', () {
      final service = ApiService();
      expect(service.dio.options.connectTimeout, const Duration(seconds: 30));
      expect(service.dio.options.receiveTimeout, const Duration(seconds: 30));
    });
  });

  group('QuickDownloadWindow Widget Tests', () {
    testWidgets('Renders input field, Video İndir, and MP3 İndir buttons', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuickDownloadWindow(initialUrl: 'https://vimeo.com/123456'),
          ),
        ),
      );

      expect(find.text('Hızlı İndirme Paneli'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Video İndir'), findsOneWidget);
      expect(find.text('MP3 İndir'), findsOneWidget);
    });

    testWidgets('Tapping download with empty URL displays error message', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: QuickDownloadWindow())),
      );

      final videoButton = find.text('Video İndir');
      await tester.tap(videoButton);
      await tester.pumpAndSettle();

      expect(
        find.text('Lütfen geçerli bir video veya ses bağlantısı yapıştırın.'),
        findsOneWidget,
      );
    });
  });
}
