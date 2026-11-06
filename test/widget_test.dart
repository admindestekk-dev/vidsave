import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'package:vid_downloader_app/batch_download_screen.dart';
import 'package:vid_downloader_app/download_platforms.dart';
import 'package:vid_downloader_app/media_library.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/home_screen.dart';
import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/more_screen.dart';
import 'package:vid_downloader_app/music_player.dart';
import 'package:vid_downloader_app/screens/in_app_media_browser_screen.dart';
import 'package:vid_downloader_app/video_player_screen.dart';
import 'package:vid_downloader_app/welcome_screen.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('VidSave opens on the download tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VidSaveHomePage(
          library: _TestMediaLibrary(),
          backendSettingsStore: _EmptyBackendSettingsStore(),
        ),
      ),
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(VidSaveBrandTitle), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
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

    final browserTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Tarayıcı'),
    );

    // From another tab, back should snap to İndir and NOT close the app.
    await tester.tap(browserTab);
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

    final browserTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Tarayıcı'),
    );
    final bulkTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Toplu İndirme'),
    );
    final moreTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Ayarlar'),
    );
    final downloadTab = find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('İndir'),
    );

    await tester.tap(browserTab);
    await tester.pumpAndSettle();
    expect(find.byType(InAppMediaBrowserScreen), findsOneWidget);

    await tester.tap(bulkTab);
    await tester.pumpAndSettle();
    expect(find.byType(BatchDownloadScreen), findsOneWidget);

    await tester.tap(moreTab);
    await tester.pumpAndSettle();
    expect(find.text('Uygulama Ayarları'), findsOneWidget);
    expect(find.text('Dil Seçimi / Language'), findsOneWidget);

    await tester.tap(downloadTab);
    await tester.pumpAndSettle();
    expect(find.text('İNDİR'), findsNWidgets(kDownloadPlatforms.length));
    expect(find.widgetWithText(TextButton, 'Tarayıcı'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Toplu İndir'), findsNothing);
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
    await tester.enterText(find.byType(TextFormField).at(1), 'test-secret');
    final saveButton = find.widgetWithText(OutlinedButton, 'Sadece Kaydet');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.settings.baseUrl, 'http://10.0.2.2:8787');
    expect(store.settings.apiKey, 'test-secret');
    expect(find.text('Ayarlar güvenli biçimde kaydedildi.'), findsOneWidget);
  });

  testWidgets('VideoPlayerScreen opens with video asset and factory', (
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
        home: VideoPlayerScreen(
          asset: asset,
          title: 'clip.mp4',
          controllerFactory: (_) => neverInitialized,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    expect(find.byTooltip('Geri'), findsOneWidget);
  });

  testWidgets('MusicPlayerScreen opens with audio file and plays audio', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('widget_aud_test');
    final audioFile = File('${tempDir.path}/track.mp3')
      ..writeAsStringSync('dummy');
    final player = _FakeMusicPlayer();

    await tester.pumpWidget(
      MaterialApp(
        home: MusicPlayerScreen(
          file: audioFile,
          title: 'track.mp3',
          playerFactory: (_) => player,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MusicPlayerScreen), findsOneWidget);
    expect(find.text('Şimdi Çalıyor'), findsOneWidget);
    expect(player.source, isA<DeviceFileSource>());
    expect(player.isPlaying, isTrue);

    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('MusicPlayerScreen seeks and updates the pause state', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('widget_music_seek');
    final audioFile = File('${tempDir.path}/track.mp3')
      ..writeAsStringSync('dummy');
    final player = _FakeMusicPlayer();
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: MusicPlayerScreen(
          file: audioFile,
          title: 'track.mp3',
          playerFactory: (_) => player,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('10 saniye ileri'));
    await tester.pump();
    expect(player.lastSeek, const Duration(seconds: 10));

    await tester.tap(find.byTooltip('Duraklat'));
    await tester.pump();
    expect(player.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('WelcomeScreen renders guest bypass button and proceeds to app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: WelcomeScreen(
          animate: false,
          homeBuilder: (_) =>
              const Scaffold(body: Center(child: Text('VidSave'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Google ile Devam Et'), findsOneWidget);
    final guestButton = find.text('Giriş Yapmadan Ücretsiz Devam Et');
    expect(guestButton, findsOneWidget);

    await tester.tap(guestButton);
    await tester.pumpAndSettle();

    expect(find.text('VidSave'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome), isTrue);
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
  Duration? lastSeek;

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
    lastSeek = position;
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
    return [];
  }

  @override
  void invalidateCache() {}
}
