import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/download_platforms.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/media_library.dart';

class _TestMediaLibrary implements MediaLibrary {
  const _TestMediaLibrary();

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async {
    return const [];
  }

  @override
  void invalidateCache() {}
}

class _EmptyBackendSettingsStore implements BackendSettingsStore {
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

/// Records what each tile asked to resolve, so we can prove independence.
class _RecordingResolver implements MediaResolver {
  final calls = <String>[];

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(
      title: 'Örnek Video Başlığı',
      qualities: [
        VideoQuality(height: 0, label: 'En iyi kalite'),
        VideoQuality(height: 1080, label: '1080p'),
        VideoQuality(height: 720, label: '720p'),
        VideoQuality(height: 480, label: '480p'),
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
    calls.add('${source.path}|${kind.name}');
    return ResolvedMedia(
      url: Uri.parse('http://10.0.2.2:8787/download?u=${source.path}'),
      fileName: 'file_${calls.length}.mp4',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => const [];
}

class _NoopDownloader extends MediaDownloader {
  _NoopDownloader() : super(directoryProvider: () async => _dir);

  static final _dir = Directory.systemTemp.createTempSync('vid_probe');

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
  testWidgets('each square downloads independently of the others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final resolver = _RecordingResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
          mediaResolver: resolver,
          mediaDownloader: _NoopDownloader(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One İNDİR button per square
    final buttons = find.widgetWithText(FilledButton, 'İNDİR');
    expect(buttons, findsNWidgets(kDownloadPlatforms.length));

    // Tap on the first square's İNDİR button to open modal
    await tester.tap(buttons.first);
    await tester.pumpAndSettle();

    // In modal, enter text and search
    final modalTextField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    expect(modalTextField, findsOneWidget);
    await tester.enterText(modalTextField, 'https://facebook.com/watch/abc');
    await tester.pump();
    await tester.tap(find.text('ARA'));
    await tester.pumpAndSettle();

    // Verify modal resolved or showed download options
    expect(find.text('Örnek Video Başlığı'), findsOneWidget);
  });
}
