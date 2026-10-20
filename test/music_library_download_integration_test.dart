import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/download_item_model.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/media_library.dart';
import 'package:vid_downloader_app/music_player.dart';
import 'package:vid_downloader_app/storage_service.dart';

class _FakeMusicPlayer implements MusicPlayerController {
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completeController = StreamController<void>.broadcast();

  Source? source;
  bool isPlaying = false;
  int resumeCount = 0;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _stateController.stream;

  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationController.stream;

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}

  @override
  Future<void> setSource(Source source) async {
    this.source = source;
  }

  @override
  Future<void> resume() async {
    resumeCount++;
    isPlaying = true;
    _stateController.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _stateController.add(PlayerState.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<Duration?> getCurrentPosition() async => Duration.zero;

  @override
  Future<Duration?> getDuration() async => const Duration(seconds: 45);

  @override
  Future<void> stop() async {
    isPlaying = false;
    _stateController.add(PlayerState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _completeController.close();
  }
}

class _MockEmptyLibrary implements MediaLibrary {
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

void main() {
  late Directory tempDir;
  late File sampleMp3;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('vidsave_music_test_');
    sampleMp3 = File('${tempDir.path}${Platform.pathSeparator}favori_sarki.mp3');
    await sampleMp3.writeAsString('sample mp3 audio content');

    // StorageService'e indirilen MP3 kaydı ekle
    await StorageService.addItem(
      DownloadItemModel(
        id: 'test-mp3-1',
        name: 'favori_sarki.mp3',
        type: 'audio',
        sizeInBytes: sampleMp3.lengthSync(),
        filePath: sampleMp3.path,
        downloadedAt: DateTime.now(),
        sourceUrl: 'https://youtube.com/watch?v=sample',
      ),
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
      'Downloaded MP3s appear in the bottom navigation "Müzik" tab and can be played',
      (tester) async {
    final fakePlayer = _FakeMusicPlayer();

    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: _MockEmptyLibrary(),
          backendSettingsStore: const _EmptyBackendSettingsStore(),
          musicPlayerFactory: (_) => fakePlayer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. En alttaki bardan Müzik sekmesine tıkla
    final musicTab = find.text('Müzik').first;
    expect(musicTab, findsOneWidget);
    await tester.tap(musicTab);
    await tester.pumpAndSettle();

    // 2. İndirilen MP3 dosyasının Müzik sekmesinde listelendiğini doğrula
    expect(find.text('favori_sarki.mp3'), findsOneWidget);

    // 3. Şarkı kartına tıkla ve müzik çaların açıldığını doğrula
    await tester.tap(find.text('favori_sarki.mp3'));
    await tester.pumpAndSettle();

    expect(find.byType(MusicPlayerScreen), findsOneWidget);
    expect(find.text('favori_sarki.mp3'), findsWidgets);
  });
}

class _EmptyBackendSettingsStore implements BackendSettingsStore {
  const _EmptyBackendSettingsStore();

  @override
  Future<BackendSettings> load() async => const BackendSettings();

  @override
  Future<void> save(BackendSettings settings) async {}
}
