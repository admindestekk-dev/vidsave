import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/quick_download_dialog.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

class _FakeMediaResolver implements MediaResolver {
  final Completer<ResolvedMedia> completer = Completer<ResolvedMedia>();

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(title: 'Test Video');
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
    return completer.future;
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'Free user: tapping download button shows Rewarded Ad Consent Dialog, cancel does not download',
      (tester) async {
    final fakeResolver = _FakeMediaResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickDownloadDialog(
            videoTitle: 'https://example.com/test.mp4',
            resolver: fakeResolver,
            downloader: MediaDownloader(),
          ),
        ),
      ),
    );

    expect(find.text('Video İndir'), findsOneWidget);
    expect(find.text('MP3 İndir'), findsOneWidget);

    // Video İndir'e basınca yasal onay penceresi açılmalı
    await tester.tap(find.text('Video İndir'));
    await tester.pumpAndSettle();

    expect(find.text('Ücretsiz İndirme Hakkı Kazan!'), findsOneWidget);
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(
      find.text(
        'Bu videoyu yüksek hızda ücretsiz indirebilmek için kısa bir reklam izlemek ister misiniz? Reklamı sonuna kadar izlediğinizde indirme işleminiz otomatik olarak başlayacaktır.',
      ),
      findsOneWidget,
    );
    expect(find.text('Vazgeç'), findsOneWidget);
    expect(find.text('Reklamı İzle ve İndir'), findsOneWidget);

    // Vazgeç'e basılırsa pencere kapanır, indirme başlamaz
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();

    expect(find.text('Ücretsiz İndirme Hakkı Kazan!'), findsNothing);
    expect(find.text('Video İndir'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'Free user: accepting consent dialog starts downloading and displays LinearProgressIndicator',
      (tester) async {
    final fakeResolver = _FakeMediaResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickDownloadDialog(
            videoTitle: 'https://example.com/test.mp4',
            resolver: fakeResolver,
            downloader: MediaDownloader(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Video İndir'));
    await tester.pumpAndSettle();

    // Reklamı İzle ve İndir butonuna bas
    await tester.tap(find.text('Reklamı İzle ve İndir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Onay penceresi kapandı ve indirme ilerleme çubuğu göründü
    expect(find.text('Video İndir'), findsNothing);
    expect(find.text('MP3 İndir'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('İndiriliyor... %0'), findsOneWidget);
    expect(find.text('0 MB/s'), findsOneWidget);
  });

  testWidgets(
      'Premium user: bypasses rewarded ad consent dialog completely and starts downloading directly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SubscriptionScreen.prefKeyIsPremium: true,
    });

    final fakeResolver = _FakeMediaResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickDownloadDialog(
            videoTitle: 'https://example.com/test.mp4',
            resolver: fakeResolver,
            downloader: MediaDownloader(),
          ),
        ),
      ),
    );

    // Premium kullanıcı butona bastığında onay pop-up'ı çıkmaz, doğrudan indirme başlar
    await tester.tap(find.text('Video İndir'));
    await tester.pump();

    expect(find.text('Ücretsiz İndirme Hakkı Kazan!'), findsNothing);
    expect(find.text('Video İndir'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('İndiriliyor... %0'), findsOneWidget);
  });
}
