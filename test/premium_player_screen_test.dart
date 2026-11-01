import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/music_player.dart';
import 'package:vid_downloader_app/premium_player_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audio player renames local file and selects quality', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory.systemTemp.createTempSync('premium_player_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final audioFile = File(
      '${directory.path}${Platform.pathSeparator}track.mp3',
    )..writeAsBytesSync([1, 2, 3]);
    var playerCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PremiumPlayerScreen(
          file: audioFile,
          title: 'track.mp3',
          audioPlayerFactory: (_) {
            playerCount++;
            return _FakeMusicPlayer();
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('track.mp3'), findsNWidgets(2));
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byKey(const Key('premium_player_share')), findsOneWidget);
    expect(find.byKey(const Key('premium_player_quality')), findsOneWidget);

    await tester.tap(find.byKey(const Key('premium_player_rename')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.tap(find.text('KAYDET'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var index = 0; index < 5; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      File('${directory.path}${Platform.pathSeparator}renamed.mp3')
          .existsSync(),
      isTrue,
    );
    expect(find.text('renamed.mp3'), findsNWidgets(2));
    expect(playerCount, 2);

    await tester.tap(find.byKey(const Key('premium_player_quality')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('720p'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('720p'), findsOneWidget);
  });
}

class _FakeMusicPlayer implements MusicPlayerController {
  final StreamController<PlayerState> _state =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<void> _complete = StreamController<void>.broadcast();

  @override
  Stream<PlayerState> get onPlayerStateChanged => _state.stream;
  @override
  Stream<Duration> get onPositionChanged => _position.stream;
  @override
  Stream<Duration> get onDurationChanged => _duration.stream;
  @override
  Stream<void> get onPlayerComplete => _complete.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}
  @override
  Future<void> setSource(Source source) async {
    _duration.add(const Duration(minutes: 2));
  }

  @override
  Future<void> resume() async => _state.add(PlayerState.playing);
  @override
  Future<void> pause() async => _state.add(PlayerState.paused);
  @override
  Future<void> seek(Duration position) async => _position.add(position);
  @override
  Future<Duration?> getCurrentPosition() async => Duration.zero;
  @override
  Future<Duration?> getDuration() async => const Duration(minutes: 2);
  @override
  Future<void> stop() async => _state.add(PlayerState.stopped);
  @override
  Future<void> dispose() async {
    await _state.close();
    await _position.close();
    await _duration.close();
    await _complete.close();
  }
}
