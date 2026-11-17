import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/api_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/home_screen.dart';

class _SettingsStore implements BackendSettingsStore {
  const _SettingsStore(this.settings);
  final BackendSettings settings;

  @override
  Future<BackendSettings> load() async => settings;

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ApiService Tests', () {
    const settingsStore = _SettingsStore(
      BackendSettings(baseUrl: 'http://127.0.0.1', apiKey: 'test-key'),
    );

    test(
      'headersForUrl only sends the API key to the configured backend',
      () async {
        final apiService = ApiService(
          baseUrl: 'http://127.0.0.1:8787',
          settingsStore: settingsStore,
        );

        expect(
          await apiService.headersForUrl(
            Uri.parse('http://127.0.0.1/download?job=video'),
          ),
          {'X-Api-Key': 'test-key'},
        );
        expect(
          await apiService.headersForUrl(
            Uri.parse('https://cdn.example/video.mp4'),
          ),
          isEmpty,
        );
      },
    );

    test('analyze resolves video stream successfully with clean headers and download_url', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path.endsWith('/api/analyze'), isTrue);
            expect(options.method, 'POST');
            expect(options.headers['X-Api-Key'], 'test-key');
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
        settingsStore: settingsStore,
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
        settingsStore: settingsStore,
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
          settingsStore: settingsStore,
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

    test('download sends the key only to the configured backend', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final directory = await Directory.systemTemp.createTemp('vidsave-api-test-');
        final receivedKeys = <String?>[];
        server.listen((request) async {
          receivedKeys.add(request.headers.value('X-Api-Key'));
          request.response.write('ok');
          await request.response.close();
        });
        final baseUrl = 'http://127.0.0.1:${server.port}';
        final service = ApiService(
          baseUrl: baseUrl,
          settingsStore: _SettingsStore(
            BackendSettings(baseUrl: baseUrl, apiKey: 'test-key'),
          ),
        );
        final backendFile = File('${directory.path}${Platform.pathSeparator}backend');
        final externalFile = File('${directory.path}${Platform.pathSeparator}external');
        try {
          await service.downloadFile(
            downloadUrl: '$baseUrl/download',
            savePath: backendFile.path,
          );
          expect(receivedKeys, ['test-key']);
          receivedKeys.clear();
          await service.downloadFile(
            downloadUrl: 'http://localhost:${server.port}/media',
            savePath: externalFile.path,
          );
          expect(receivedKeys, isNotEmpty);
          expect(receivedKeys.every((key) => key == null), isTrue);
        } finally {
          await server.close(force: true);
          if (backendFile.existsSync()) await backendFile.delete();
          if (externalFile.existsSync()) await externalFile.delete();
          await directory.delete();
        }
      }, _RealHttpOverrides());
    });

    test('backend download rejects rate-limited responses', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final directory = await Directory.systemTemp.createTemp('vidsave-api-test-');
        server.listen((request) async {
          request.response.statusCode = 429;
          await request.response.close();
        });
        final baseUrl = 'http://127.0.0.1:${server.port}';
        final service = ApiService(
          baseUrl: baseUrl,
          settingsStore: _SettingsStore(
            BackendSettings(baseUrl: baseUrl, apiKey: 'test-key'),
          ),
        );
        final file = File('${directory.path}${Platform.pathSeparator}download');
        try {
          await expectLater(
            service.downloadFile(downloadUrl: '$baseUrl/download', savePath: file.path),
            throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
          );
          expect(file.existsSync(), isFalse);
        } finally {
          await server.close(force: true);
          if (file.existsSync()) await file.delete();
          await directory.delete();
        }
      }, _RealHttpOverrides());
    });

    test('buildAggressiveBrowserHeaders sets Accept-Encoding to identity and Connection to keep-alive', () {
      final headers = ApiService.buildAggressiveBrowserHeaders(
        uri: Uri.parse('https://example.com/media.mp4'),
      );
      expect(headers['Accept-Encoding'], 'identity');
      expect(headers['Connection'], 'keep-alive');
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

    testWidgets('HomeScreen renders and initializes preview data state variables', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(QuickDownloadWindow), findsOneWidget);
    });
  });
}
