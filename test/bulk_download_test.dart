import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/bulk_download_screen.dart';
import 'package:vid_downloader_app/bulk_download_service.dart';
import 'package:vid_downloader_app/media_downloader.dart';

class _FakeResolver implements MediaResolver {
  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'Toplu Video',
      qualities: [VideoQuality(height: 720, label: '720p')],
    );
  }

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
  }) async {
    return ResolvedMedia(
      url: Uri.parse('http://10.0.2.2:8787/download?u=${source.path}'),
      fileName: 'bulk_video.mp4',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => [];
}

class _FakeDownloader extends MediaDownloader {
  @override
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    onProgress?.call(100, 100);
    final tempFile = File('${Directory.systemTemp.path}/test_bulk.mp4');
    tempFile.writeAsStringSync('dummy content');
    return tempFile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BulkDownloadService.parseBulkUrls', () {
    test('splits lines and filters clean URLs', () {
      const input = '''
        https://instagram.com/reel/123
        
        https://tiktok.com/@user/video/456   
        not a url
        http://youtube.com/watch?v=789
      ''';

      final urls = BulkDownloadService.parseBulkUrls(input);
      expect(urls.length, 3);
      expect(urls[0], 'https://instagram.com/reel/123');
      expect(urls[1], 'https://tiktok.com/@user/video/456');
      expect(urls[2], 'http://youtube.com/watch?v=789');
    });

    test('deduplicates identical URLs', () {
      const input = '''
        https://instagram.com/reel/123
        https://instagram.com/reel/123
      ''';

      final urls = BulkDownloadService.parseBulkUrls(input);
      expect(urls.length, 1);
    });

    test('returns empty list for empty or whitespace-only input', () {
      expect(BulkDownloadService.parseBulkUrls(''), isEmpty);
      expect(BulkDownloadService.parseBulkUrls('   \n\n  '), isEmpty);
    });
  });

  group('BulkDownloadService.sendBulkDownloadRequest', () {
    test('sends POST to /api/toplu-indir with correct headers and JSON payload', () async {
      late Uri requestedUri;
      late Map<String, String> requestedHeaders;
      late Map<String, dynamic> requestedBody;

      final mockClient = MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;

        return http.Response(
          jsonEncode({
            'status': 'ok',
            'kind': 'video',
            'total': 2,
            'items': [
              {'url': 'https://a.com', 'job': 'job_1', 'status': 'pending'},
              {'url': 'https://b.com', 'job': 'job_2', 'status': 'pending'},
            ],
          }),
          200,
        );
      });

      final settings = BackendSettings.fromInput(
        baseUrl: 'http://127.0.0.1:8787',
        apiKey: 'secret_key',
      );

      final result = await BulkDownloadService.sendBulkDownloadRequest(
        urls: ['https://a.com', 'https://b.com'],
        kind: DownloadKind.video,
        settings: settings,
        client: mockClient,
      );

      expect(requestedUri.path, '/api/toplu-indir');
      expect(requestedHeaders['X-Api-Key'], 'secret_key');
      expect(requestedHeaders['Content-Type'], 'application/json');
      expect(requestedBody['kind'], 'video');
      expect(requestedBody['urls'], ['https://a.com', 'https://b.com']);
      expect(result['status'], 'ok');
      expect(result['total'], 2);
    });
  });

  group('BulkDownloadScreen UI', () {
    testWidgets('renders TextField with maxLines 6, type choice chips and start button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BulkDownloadScreen(
            resolver: _FakeResolver(),
            downloader: _FakeDownloader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toplu İndirme (Bulk Download)'), findsOneWidget);
      expect(find.text('Video (MP4)'), findsOneWidget);
      expect(find.text('Müzik (MP3)'), findsOneWidget);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 6);

      expect(find.text('Algılanan Bağlantı: 0'), findsOneWidget);

      // Enter 2 URLs
      await tester.enterText(
        find.byType(TextField),
        'https://instagram.com/reel/1\nhttps://tiktok.com/2',
      );
      await tester.pump();

      expect(find.text('Algılanan Bağlantı: 2'), findsOneWidget);
      expect(find.text('Toplu İndirmeyi Başlat (2 Link)'), findsOneWidget);

      // Tap start bulk download
      await tester.tap(find.text('Toplu İndirmeyi Başlat (2 Link)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });
  });
}
