import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/admob_native_ad_widget.dart';
import 'package:vid_downloader_app/download_item_model.dart';
import 'package:vid_downloader_app/downloads_screen.dart';
import 'package:vid_downloader_app/music_player.dart';
import 'package:vid_downloader_app/storage_service.dart';
import 'package:vid_downloader_app/video_player_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.clearAll();
  });

  testWidgets('DownloadsScreen lists downloaded items and shows filter chips', (
    WidgetTester tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('vidsave_test');
    final videoFile = File('${tempDir.path}/test_video.mp4')
      ..writeAsStringSync('dummy video');
    final audioFile = File('${tempDir.path}/test_song.mp3')
      ..writeAsStringSync('dummy audio');

    await StorageService.addItem(
      DownloadItemModel(
        id: 'v1',
        name: 'test_video.mp4',
        type: 'video',
        sizeInBytes: 1048576,
        filePath: videoFile.path,
        downloadedAt: DateTime.now(),
      ),
    );

    await StorageService.addItem(
      DownloadItemModel(
        id: 'a1',
        name: 'test_song.mp3',
        type: 'audio',
        sizeInBytes: 524288,
        filePath: audioFile.path,
        downloadedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('İndirilenler'), findsOneWidget);
    expect(find.text('Tümü'), findsOneWidget);
    expect(find.text('Videolar'), findsOneWidget);
    expect(find.text('Müzikler (MP3)'), findsOneWidget);

    expect(find.text('test_video.mp4'), findsOneWidget);
    expect(find.text('test_song.mp3'), findsOneWidget);

    // Filter to videos only
    await tester.tap(find.text('Videolar'));
    await tester.pumpAndSettle();
    expect(find.text('test_video.mp4'), findsOneWidget);
    expect(find.text('test_song.mp3'), findsNothing);

    // Filter to audio only
    await tester.tap(find.text('Müzikler (MP3)'));
    await tester.pumpAndSettle();
    expect(find.text('test_song.mp3'), findsOneWidget);
    expect(find.text('test_video.mp4'), findsNothing);

    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'VideoPlayerScreen and MusicPlayerScreen can be instantiated with file',
    (WidgetTester tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'vidsave_player_test',
      );
      final videoFile = File('${tempDir.path}/vid.mp4')
        ..writeAsStringSync('data');
      final audioFile = File('${tempDir.path}/aud.mp3')
        ..writeAsStringSync('data');

      expect(VideoPlayerScreen(file: videoFile, title: 'vid.mp4'), isNotNull);
      expect(MusicPlayerScreen(file: audioFile, title: 'aud.mp3'), isNotNull);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    },
  );

  testWidgets(
    'DownloadsScreen embeds AdmobNativeAdWidget in the middle of download history',
    (WidgetTester tester) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'vidsave_native_ad_test',
      );
      final file1 = File('${tempDir.path}/file1.mp4')..writeAsStringSync('1');
      final file2 = File('${tempDir.path}/file2.mp4')..writeAsStringSync('2');

      await StorageService.addItem(
        DownloadItemModel(
          id: '1',
          name: 'file1.mp4',
          type: 'video',
          sizeInBytes: 100,
          filePath: file1.path,
          downloadedAt: DateTime.now(),
        ),
      );
      await StorageService.addItem(
        DownloadItemModel(
          id: '2',
          name: 'file2.mp4',
          type: 'video',
          sizeInBytes: 200,
          filePath: file2.path,
          downloadedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(AdmobNativeAdWidget), findsOneWidget);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    },
  );
}
