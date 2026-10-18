import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/media_library.dart';

class _MockMediaLibrary implements MediaLibrary {
  const _MockMediaLibrary();

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async =>
      const [];

  @override
  void invalidateCache() {}
}

class _MockSettingsStore implements BackendSettingsStore {
  BackendSettings settings = BackendSettings.fromInput(
    baseUrl: 'http://10.0.2.2:8787',
    apiKey: '',
  );

  @override
  Future<BackendSettings> load() async => settings;

  @override
  Future<void> save(BackendSettings value) async {
    settings = value;
  }
}

class _MockResolver implements MediaResolver {
  final resolvedCalls = <String>[];

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'Örnek FB Eğlenceli Video',
      qualities: [
        VideoQuality(height: 1080, label: '1080p Full HD', sizeInBytes: 52428800),
        VideoQuality(height: 720, label: '720p HD', sizeInBytes: 26214400),
        VideoQuality(height: 480, label: '480p Standart', sizeInBytes: 13107200),
      ],
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
    resolvedCalls.add('${source.path}|height=$height');
    return ResolvedMedia(
      url: Uri.parse('http://10.0.2.2:8787/media.mp4'),
      fileName: 'fb_video_${height ?? 0}.mp4',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async {
    return [
      SearchResultItem(
        id: '1',
        baslik: '$query Şarkısı 1',
        kanal: 'Sanatçı Kanalı',
        sure: '3:45',
        url: 'https://youtube.com/watch?v=mock1',
      ),
      SearchResultItem(
        id: '2',
        baslik: '$query Şarkısı 2',
        kanal: 'Müzik Prodüksiyon',
        sure: '4:12',
        url: 'https://youtube.com/watch?v=mock2',
      ),
    ];
  }
}

class _MockDownloader extends MediaDownloader {
  _MockDownloader() : super(directoryProvider: () async => _dir);
  static final _dir = Directory.systemTemp.createTempSync('platform_test');

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
  testWidgets('tapping platform tile opens search modal and allows downloading specific quality directly', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final resolver = _MockResolver();
    final downloader = _MockDownloader();

    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: const _MockMediaLibrary(),
          backendSettingsStore: _MockSettingsStore(),
          mediaResolver: resolver,
          mediaDownloader: downloader,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap on Facebook square tile (FB VİDEO İNDİR)
    final fbTile = find.text('FB VİDEO İNDİR');
    expect(fbTile, findsOneWidget);
    await tester.tap(fbTile);
    await tester.pumpAndSettle();

    // Verify platform search modal opened
    expect(find.text('Video ara veya bağlantı yapıştırın'), findsOneWidget);
    expect(find.text('ARA'), findsOneWidget);

    // Enter search query
    final searchInput = find.widgetWithText(TextField, 'Video ara veya bağlantı yapıştırın');
    await tester.enterText(searchInput, 'https://facebook.com/reel/12345');
    await tester.pump();

    // Click ARA button
    await tester.tap(find.text('ARA'));
    await tester.pumpAndSettle();

    // Verify video title and qualities with their own INDIR buttons
    expect(find.text('Örnek FB Eğlenceli Video'), findsOneWidget);
    expect(find.text('1080p Full HD'), findsOneWidget);
    expect(find.text('720p HD'), findsOneWidget);
    expect(find.text('480p Standart'), findsOneWidget);

    // Each quality has its own INDIR button beside it
    final indirButtons = find.text('İNDİR');
    expect(indirButtons, findsWidgets);

    // Click download on 720p HD quality
    final hd720QualityContainer = find.ancestor(
      of: find.text('720p HD'),
      matching: find.byType(Container),
    );
    final hd720DownloadBtn = find.descendant(
      of: hd720QualityContainer,
      matching: find.byKey(const ValueKey('quality_720')),
    );
    expect(hd720DownloadBtn, findsOneWidget);
    await tester.tap(hd720DownloadBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Confirm that 720 was resolved
    expect(resolver.resolvedCalls.any((call) => call.contains('height=720')), isTrue);
  });

  testWidgets('tapping Pinterest platform tile opens search modal with correct styling and allowed domains', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final resolver = _MockResolver();
    final downloader = _MockDownloader();

    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: const _MockMediaLibrary(),
          backendSettingsStore: _MockSettingsStore(),
          mediaResolver: resolver,
          mediaDownloader: downloader,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Pinterest card is present on grid
    final pinterestTile = find.text('PINTEREST İNDİRİCİ');
    expect(pinterestTile, findsOneWidget);
    await tester.ensureVisible(pinterestTile);
    await tester.tap(pinterestTile);
    await tester.pumpAndSettle();

    // Verify Pinterest search modal opened with appropriate hints
    expect(find.text('PINTEREST İNDİRİCİ'), findsWidgets);
    expect(find.text('pinterest.com veya pin.it linki yapıştırın veya arayın'), findsOneWidget);

    final searchInput = find.byType(TextField);
    await tester.enterText(searchInput, 'https://www.pinterest.com/pin/123456789/');
    await tester.pump();

    await tester.tap(find.text('ARA'));
    await tester.pumpAndSettle();

    expect(find.text('Örnek FB Eğlenceli Video'), findsOneWidget);
  });
}
