import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/admob_service.dart';
import 'package:vid_downloader_app/batch_download_screen.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

class _FakeResolver implements MediaResolver {
  final List<String> resolvedUrls = [];

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'Batch Test Video',
      qualities: [VideoQuality(height: 720, label: '720p')],
    );
  }

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    resolvedUrls.add(source.toString());
    return ResolvedMedia(
      url: Uri.parse('http://example.com/download.mp4'),
      fileName: 'batch_item_${resolvedUrls.length}.mp4',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => [];
}

class _FakeDownloader extends MediaDownloader {
  final List<String> downloadedFiles = [];

  @override
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    onProgress?.call(50, 100);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    onProgress?.call(100, 100);
    final tempFile = File('${Directory.systemTemp.path}/${media.fileName}');
    tempFile.writeAsStringSync('dummy content');
    downloadedFiles.add(media.fileName);
    return tempFile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AdmobService.instance.disableAdsForTesting = true;
  });

  group('BatchDownloadScreen - Dynamic Rows & UI Architecture', () {
    testWidgets('renders 1 default empty row with "1.", TextField, and delete icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BatchDownloadScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toplu İndirme'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('Yeni Link Satırı Ekle'), findsOneWidget);
      expect(find.text('Toplu İndirmeyi Başlat'), findsOneWidget);
    });

    testWidgets('tapping "Yeni Link Satırı Ekle" adds new row dynamically', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BatchDownloadScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsNothing);

      // Tap add button
      await tester.tap(find.text('Yeni Link Satırı Ekle'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);

      // Tap add button again
      await tester.tap(find.text('Yeni Link Satırı Ekle'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('3.'), findsOneWidget);
    });

    testWidgets('tapping delete button removes row from list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BatchDownloadScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Add two more rows (total 3)
      await tester.tap(find.text('Yeni Link Satırı Ekle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni Link Satırı Ekle'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(3));

      // Enter distinct text in row 1, 2, 3
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'https://test1.com');
      await tester.enterText(textFields.at(1), 'https://test2.com');
      await tester.enterText(textFields.at(2), 'https://test3.com');
      await tester.pumpAndSettle();

      expect(find.text('https://test2.com'), findsOneWidget);

      // Delete 2nd row
      final deleteButtons = find.byIcon(Icons.delete_outline);
      await tester.tap(deleteButtons.at(1));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('https://test2.com'), findsNothing);
      expect(find.text('https://test1.com'), findsOneWidget);
      expect(find.text('https://test3.com'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsNothing);
    });

    testWidgets('empty link input triggers warning SnackBar when starting batch download', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BatchDownloadScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Toplu İndirmeyi Başlat'));
      await tester.pumpAndSettle();

      expect(
        find.text('Lütfen indirmek için en az bir geçerli video veya müzik linki girin.'),
        findsOneWidget,
      );
    });
  });

  group('BatchDownloadScreen - Queue & Rewarded Ad Consent Flow', () {
    testWidgets('Free user gets AdMob Rewarded Consent Dialog before starting queue', (
      WidgetTester tester,
    ) async {
      final fakeResolver = _FakeResolver();
      final fakeDownloader = _FakeDownloader();

      // Mock free user (isPremium = false)
      SharedPreferences.setMockInitialValues({
        SubscriptionScreen.prefKeyIsPremium: false,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BatchDownloadScreen(
            resolver: fakeResolver,
            downloader: fakeDownloader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter valid link
      await tester.enterText(find.byType(TextField).first, 'https://instagram.com/reel/abc');
      await tester.pumpAndSettle();

      // Tap start
      await tester.tap(find.text('Toplu İndirmeyi Başlat (1 Link)'));
      await tester.pumpAndSettle();

      // Verify AdMob Rewarded Consent Dialog appears
      expect(find.text('Ücretsiz İndirme Hakkı Kazan!'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(find.text('Reklamı İzle ve Başlat'), findsOneWidget);

      // Tap "Vazgeç" -> queue should NOT start
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(fakeResolver.resolvedUrls, isEmpty);
      expect(fakeDownloader.downloadedFiles, isEmpty);

      // Tap start again and confirm
      await tester.tap(find.text('Toplu İndirmeyi Başlat (1 Link)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reklamı İzle ve Başlat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(fakeResolver.resolvedUrls.length, 1);
      expect(fakeDownloader.downloadedFiles.length, 1);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Premium user directly bypasses AdMob dialog and executes sequential download', (
      WidgetTester tester,
    ) async {
      final fakeResolver = _FakeResolver();
      final fakeDownloader = _FakeDownloader();

      // Mock premium user (isPremium = true)
      SharedPreferences.setMockInitialValues({
        SubscriptionScreen.prefKeyIsPremium: true,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BatchDownloadScreen(
            resolver: fakeResolver,
            downloader: fakeDownloader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add two rows
      await tester.tap(find.text('Yeni Link Satırı Ekle'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'https://tiktok.com/@user/video/1');
      await tester.enterText(textFields.at(1), 'https://youtube.com/watch?v=2');
      await tester.pumpAndSettle();

      // Tap start
      await tester.tap(find.text('Toplu İndirmeyi Başlat (2 Link)'));
      await tester.pump();

      // No consent dialog should be shown for premium user
      expect(find.text('Ücretsiz İndirme Hakkı Kazan!'), findsNothing);

      // Let queue finish
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(fakeResolver.resolvedUrls.length, 2);
      expect(fakeDownloader.downloadedFiles.length, 2);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    });
  });
}
