import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vid_downloader_app/backend_media_resolver.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/media_downloader.dart';

void main() {
  group('BackendSettings', () {
    test(
      'uses the default unless a build define overrides it',
      () {
        expect(BackendSettings.defaultBaseUrl, 'https://vidsave-q7ut.onrender.com');
      },
    );

    test('normalizes a valid backend URL', () {
      final settings = BackendSettings.fromInput(
        baseUrl: 'http://10.0.2.2:8787/',
        apiKey: ' secret ',
      );

      expect(settings.baseUrl, 'http://10.0.2.2:8787');
      expect(settings.baseUri.toString(), 'http://10.0.2.2:8787');
      expect(settings.apiKey, 'secret');
    });

    test('rejects non-HTTP URLs and paths', () {
      expect(
        () =>
            BackendSettings.fromInput(baseUrl: 'ftp://example.com', apiKey: ''),
        throwsFormatException,
      );
      expect(
        () => BackendSettings.fromInput(
          baseUrl: 'https://example.com/backend',
          apiKey: '',
        ),
        throwsFormatException,
      );
    });
  });

  group('BackendMediaResolver', () {
    const settings = BackendSettings(
      baseUrl: 'https://vidsave.example',
      apiKey: 'secret',
    );

    test(
      'posts kind and API key then resolves the relative download URL',
      () async {
        final client = MockClient((request) async {
          expect(request.url.toString(), 'https://vidsave.example/api/resolve');
          expect(request.headers['X-Api-Key'], 'secret');
          expect(jsonDecode(request.body), {
            'url': 'https://media.example/watch?v=123',
            'kind': 'audio',
          });
          return http.Response(
            jsonEncode({
              'status': 'ready',
              'job': 'job-1',
              'url': '/download?job=job-1',
              'filename': 'track.mp3',
              'mime': 'audio/mpeg',
              'fileSizeInBytes': 2048,
            }),
            200,
          );
        });
        final resolver = BackendMediaResolver(
          settingsStore: _MemoryBackendSettingsStore(settings),
          client: client,
        );

        final media = await resolver.resolve(
          Uri.parse('https://media.example/watch?v=123'),
          DownloadKind.audio,
        );

        expect(
          media.url.toString(),
          'https://vidsave.example/download?job=job-1',
        );
        expect(media.fileName, 'track.mp3');
        expect(media.mimeType, 'audio/mpeg');
        expect(media.fileSizeInBytes, 2048);
        expect(media.downloadHeaders, {'X-Api-Key': 'secret'});
        client.close();
      },
    );

    test('polls pending job using its job identifier', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (requests == 1) {
          expect(body.containsKey('job'), isFalse);
          return http.Response(
            jsonEncode({'status': 'running', 'job': 'job-2'}),
            200,
          );
        }
        expect(body['job'], 'job-2');
        return http.Response(
          jsonEncode({
            'status': 'ready',
            'job': 'job-2',
            'url': '/download?job=job-2',
            'filename': 'clip.mp4',
          }),
          200,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
        delay: (_) async {},
      );

      final media = await resolver.resolve(
        Uri.parse('https://media.example/watch'),
        DownloadKind.video,
      );

      expect(requests, 2);
      expect(media.fileName, 'clip.mp4');
      client.close();
    });

    test('preview requests info and parses available qualities', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/resolve');
        expect(jsonDecode(request.body), {
          'url': 'https://media.example/watch?v=456',
          'kind': 'video',
          'info': true,
        });
        return http.Response(
          jsonEncode({
            'status': 'info',
            'title': 'Test Video',
            'duration': 185,
            'uploader': 'Test Channel',
            'qualities': [
              {'height': 1080, 'label': '1080p', 'sizeInBytes': 50000000},
              {'height': 720, 'label': '720p', 'sizeInBytes': 25000000},
            ],
          }),
          200,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
      );

      final preview = await resolver.preview(
        Uri.parse('https://media.example/watch?v=456'),
        DownloadKind.video,
      );

      expect(preview.title, 'Test Video');
      expect(preview.duration?.inSeconds, 185);
      expect(preview.uploader, 'Test Channel');
      expect(preview.qualities.length, 2);
      expect(preview.qualities[0].height, 1080);
      expect(preview.qualities[0].label, '1080p');
      expect(preview.qualities[1].height, 720);
      client.close();
    });

    test('resolve passes chosen height parameter to backend', () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {
          'url': 'https://media.example/watch?v=789',
          'kind': 'video',
          'height': 720,
        });
        return http.Response(
          jsonEncode({
            'status': 'ready',
            'job': 'job-3',
            'url': '/download?job=job-3',
            'filename': 'video_720p.mp4',
          }),
          200,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
      );

      final media = await resolver.resolve(
        Uri.parse('https://media.example/watch?v=789'),
        DownloadKind.video,
        height: 720,
      );

      expect(media.fileName, 'video_720p.mp4');
      client.close();
    });

    test('surfaces backend string errors', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'status': 'error', 'error': 'Kaynak engellendi.'}),
          422,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
      );

      await expectLater(
        resolver.resolve(
          Uri.parse('https://media.example/watch'),
          DownloadKind.video,
        ),
        throwsA(
          isA<MediaResolverException>().having(
            (error) => error.message,
            'message',
            'Kaynak engellendi.',
          ),
        ),
      );
      client.close();
    });

    test('does not accept a download URL on a different host', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'ready',
            'url': 'https://attacker.example/download?job=1',
          }),
          200,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
      );

      await expectLater(
        resolver.resolve(
          Uri.parse('https://media.example/watch'),
          DownloadKind.video,
        ),
        throwsA(isA<MediaResolverException>()),
      );
      client.close();
    });

    test('testConnection includes the saved API key', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/health');
        expect(request.headers['X-Api-Key'], 'secret');
        return http.Response(
          jsonEncode({'status': 'ok', 'authRequired': true}),
          200,
        );
      });
      final resolver = BackendMediaResolver(
        settingsStore: _MemoryBackendSettingsStore(settings),
        client: client,
      );

      await resolver.testConnection();
      client.close();
    });
  });
}

class _MemoryBackendSettingsStore implements BackendSettingsStore {
  const _MemoryBackendSettingsStore(this.settings);

  final BackendSettings settings;

  @override
  Future<BackendSettings> load() async => settings;

  @override
  Future<void> save(BackendSettings value) async {}
}
