import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'package:vid_downloader_app/download_platforms.dart';
import 'package:vid_downloader_app/media_library.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/more_screen.dart';
import 'package:vid_downloader_app/music_player.dart';
import 'package:vid_downloader_app/video_player_screen.dart';

void main() {
  testWidgets('VidSave opens on the download tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
        ),
      ),
    );

    expect(find.text('VidSave'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      2,
    );
    // Platform kareleri ve altlarındaki İNDİR butonları
    expect(find.text('İNDİR'), findsNWidgets(kDownloadPlatforms.length));
  });

  testWidgets('back button returns to the İndir tab before leaving the app', (
    WidgetTester tester,
  ) async {
    // Capture Android's "pop the app" request instead of actually closing it.
    final navigatorCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        navigatorCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    BottomNavigationBar navBar() =>
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));

    // From another tab, back should snap to İndir and NOT close the app.
    await tester.tap(find.text('Videolar').first);
    await tester.pumpAndSettle();
    expect(navBar().currentIndex, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(navBar().currentIndex, 2);
    expect(
      navigatorCalls.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
    );

    // Already on İndir, back may now leave the app.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      navigatorCalls.where((c) => c.method == 'SystemNavigator.pop'),
      isNotEmpty,
    );
  });

  testWidgets('bottom navigation switches between pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Videolar').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Cihazda gösterilecek videolar bulunamadı.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Müzik').first);
    await tester.pumpAndSettle();
    expect(find.text('Cihazda gösterilecek müzik bulunamadı.'), findsOneWidget);

    await tester.tap(find.text('Ayarlar').first);
    await tester.pumpAndSettle();
    expect(find.text('Uygulama Ayarları'), findsOneWidget);
    expect(find.text('Dil Seçimi / Language'), findsOneWidget);

    await tester.tap(find.text('İndir').first);
    await tester.pumpAndSettle();
    expect(find.text('İNDİR'), findsNWidgets(kDownloadPlatforms.length));
  });

  testWidgets('backend settings validate and persist entered credentials', (
    WidgetTester tester,
  ) async {
    // Gizli geliştirici formu uzun; buton ekran dışında kalmasın diye
    // test ekranını daha yüksek bir çözünürlükte çalıştır.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _TestBackendSettingsStore();
    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: const _TestMediaLibrary(),
          backendSettingsStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayarlar').first);
    await tester.pumpAndSettle();

    // Gizli geliştirici bölümünü açmak için başlığa 5 kez dokun.
    // Başlık, MoreScreen içindeki GestureDetector'da; AppBar başlığıyla
    // karışmaması için descendant ile hedeflenir.
    final titleFinder = find.descendant(
      of: find.byType(MoreScreen),
      matching: find.text('VidSave'),
    );
    expect(titleFinder, findsOneWidget);
    final titleCenter = tester.getCenter(titleFinder);
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(titleCenter);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Geliştirici Bölümü'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'http://10.0.2.2:8787',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'test-secret',
    );
    final saveButton = find.widgetWithText(OutlinedButton, 'Sadece Kaydet');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.settings.baseUrl, 'http://10.0.2.2:8787');
    expect(store.settings.apiKey, 'test-secret');
    expect(find.text('Ayarlar güvenli biçimde kaydedildi.'), findsOneWidget);
  });

  testWidgets('tapping a video opens the full-screen player', (
    WidgetTester tester,
  ) async {
    final asset = AssetEntity(
      id: 'test-video',
      typeInt: AssetType.video.index,
      width: 1920,
      height: 1080,
      duration: 45,
      title: 'clip.mp4',
      createDateSecond: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final neverInitialized = Completer<VideoPlayerController>().future;
    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(assets: [asset]),
          backendSettingsStore: _EmptyBackendSettingsStore(),
          videoPlayerControllerFactory: (_) => neverInitialized,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Videolar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Card).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(find.text('clip.mp4'), findsNWidgets(2));
    expect(find.byTooltip('Geri'), findsOneWidget);

    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayerScreen), findsNothing);
  });

  testWidgets('tapping music opens the player and starts playback', (
    WidgetTester tester,
  ) async {
    final asset = AssetEntity(
      id: 'test-audio',
      typeInt: AssetType.audio.index,
      width: 0,
      height: 0,
      duration: 45,
      title: 'track.mp3',
      createDateSecond: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    final player = _FakeMusicPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(assets: [asset]),
          backendSettingsStore: _EmptyBackendSettingsStore(),
          musicPlayerFactory: (_) => player,
          musicSourceResolver: (_) async => UrlSource('file:///track.mp3'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Müzik').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Card).first);
    await tester.pumpAndSettle();

    expect(find.byType(MusicPlayerScreen), findsOneWidget);
    expect(find.text('Şimdi Çalıyor'), findsOneWidget);
    expect(player.source, isA<UrlSource>());
    expect(player.isPlaying, isTrue);
    expect(player.resumeCount, 1);

    await tester.tap(find.byTooltip('Geri'));
    await tester.pumpAndSettle();
  });
}

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

class _EmptyBackendSettingsStore implements BackendSettingsStore {
  const _EmptyBackendSettingsStore();

  @override
  Future<BackendSettings> load() async => const BackendSettings();

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _TestBackendSettingsStore implements BackendSettingsStore {
  BackendSettings settings = const BackendSettings();

  @override
  Future<BackendSettings> load() async => settings;

  @override
  Future<void> save(BackendSettings value) async => settings = value;
}

class _TestMediaLibrary implements MediaLibrary {
  const _TestMediaLibrary({this.assets = const []});

  final List<AssetEntity> assets;

  @override
  Future<PermissionState> requestPermission() async =>
      PermissionState.authorized;

  @override
  Future<List<AssetEntity>> loadPage({
    required RequestType type,
    required int page,
    required int pageSize,
  }) async {
    if (page == 0) return assets;
    return [];
  }

  @override
  void invalidateCache() {}
}
