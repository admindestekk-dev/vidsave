import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/download_platforms.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_downloader.dart';

class _FakeMusicResolver implements MediaResolver {
  final resolveCalls = <String>[];

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'Örnek Başlık',
      qualities: [VideoQuality(height: 0, label: 'En İyi')],
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
    resolveCalls.add('${source.path}|${kind.name}');
    return ResolvedMedia(
      url: Uri.parse('http://10.0.2.2:8787/download'),
      fileName: 'sarki.mp3',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async {
    return [
      SearchResultItem(
        id: '1',
        baslik: '$query - Ateşten Gömlek',
        kanal: 'Kolera & Sagopa',
        sure: '4:20',
        url: 'https://youtube.com/watch?v=sago1',
      ),
      SearchResultItem(
        id: '2',
        baslik: '$query - Galiba',
        kanal: 'Melankolia Müzik',
        sure: '3:50',
        url: 'https://youtube.com/watch?v=sago2',
      ),
    ];
  }
}

class _FakeMusicDownloader extends MediaDownloader {
  _FakeMusicDownloader() : super(directoryProvider: () async => _dir);
  static final _dir = Directory.systemTemp.createTempSync('music_test');

  @override
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final file = File('${_dir.path}/${media.fileName}');
    await file.writeAsBytes(const [1, 2, 3]);
    onProgress?.call(3, 3);
    return file;
  }
}

void main() {
  testWidgets('MP3 search lists multiple songs and downloads on click', (tester) async {
    final resolver = _FakeMusicResolver();
    final downloader = _FakeMusicDownloader();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => PlatformSearchDownloadModal(
                      platform: kDownloadPlatforms.firstWhere((p) => p.isAudio),
                      resolver: resolver,
                      downloader: downloader,
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();

    expect(find.text('MP3 İNDİR'), findsOneWidget);
    expect(find.text('ARA'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.enterText(input, 'Sagopa Kajmer');
    await tester.pump();

    await tester.tap(find.text('ARA'));
    await tester.pumpAndSettle();

    expect(find.text('Sagopa Kajmer - Ateşten Gömlek'), findsOneWidget);
    expect(find.text('Kolera & Sagopa'), findsOneWidget);
    expect(find.text('4:20'), findsOneWidget);

    expect(find.text('Sagopa Kajmer - Galiba'), findsOneWidget);
    expect(find.text('Melankolia Müzik'), findsOneWidget);
    expect(find.text('3:50'), findsOneWidget);

    // Tap first song item card to trigger download
    final firstSong = find.text('Sagopa Kajmer - Ateşten Gömlek');
    await tester.ensureVisible(firstSong);
    await tester.tap(firstSong);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(resolver.resolveCalls.isNotEmpty, isTrue);
  });

  testWidgets('MP3 modal allows pasting YouTube URL, fetching preview and downloading MP3', (tester) async {
    final resolver = _FakeMusicResolver();
    final downloader = _FakeMusicDownloader();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => PlatformSearchDownloadModal(
                      platform: kDownloadPlatforms.firstWhere((p) => p.isAudio),
                      resolver: resolver,
                      downloader: downloader,
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();

    // Enter YouTube URL into TextField
    final input = find.byType(TextField);
    await tester.enterText(input, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    await tester.pump();

    // Tap ARA button to fetch preview
    await tester.tap(find.text('ARA'));
    await tester.pumpAndSettle();

    // Verify preview title and MP3 quality options are shown
    expect(find.text('Örnek Başlık'), findsOneWidget);
    expect(find.text('MP3 SES DÖNÜŞTÜRME SEÇENEKLERİ'), findsOneWidget);
    expect(find.text('MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)'), findsOneWidget);

    // Tap the MP3 download button beside 320 kbps (height: 0)
    final downloadButton = find.byKey(const ValueKey('quality_0'));
    expect(downloadButton, findsOneWidget);
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(resolver.resolveCalls.any((call) => call.contains('audio')), isTrue);
  });
}
