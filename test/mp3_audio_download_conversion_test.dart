import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/services/unified_download_engine.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

class _FakeVideoResolver implements MediaResolver {
  _FakeVideoResolver(this.resolvedFile);
  final File resolvedFile;

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(title: 'Test Video Preview');
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
    return ResolvedMedia(
      url: Uri.parse('https://example.com/tiktok_video.mp4'),
      fileName: 'tiktok_sample_video.mp4',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => const [];
}

class _FakeVideoDownloader extends MediaDownloader {
  _FakeVideoDownloader(this.fakeDownloadedFile);
  final File fakeDownloadedFile;

  @override
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    return fakeDownloadedFile;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('mp3_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('MP3 Audio Format & Conversion Validation', () {
    test('isGenuineMp3File correctly detects ID3v2 and MPEG frame sync, rejects MP4 ftyp', () async {
      // 1. MP3 with ID3v2 tag: "ID3"
      final id3File = File('${tempDir.path}/test_id3.mp3');
      await id3File.writeAsBytes([
        0x49,
        0x44,
        0x33,
        0x03,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(await MediaDownloader.isGenuineMp3File(id3File), isTrue);

      // 2. MP3 with raw MPEG sync frame: 0xFF, 0xFB (MPEG-1 Layer 3)
      final mpegFile = File('${tempDir.path}/test_mpeg.mp3');
      await mpegFile.writeAsBytes([
        0xFF,
        0xFB,
        0x90,
        0x64,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);
      expect(await MediaDownloader.isGenuineMp3File(mpegFile), isTrue);

      // 3. MP4 / M4A file with ftyp header: [0x00, 0x00, 0x00, 0x1C, 'f', 't', 'y', 'p', 'M', '4', 'A', ' ']
      final mp4File = File('${tempDir.path}/test_fake_mp3.mp3');
      await mp4File.writeAsBytes([
        0x00,
        0x00,
        0x00,
        0x1C,
        0x66,
        0x74,
        0x79,
        0x70,
        0x4D,
        0x34,
        0x41,
        0x20,
      ]);
      expect(await MediaDownloader.isGenuineMp3File(mp4File), isFalse);
    });

    test('UniversalScraper.resolve ensures fileName ends with .mp3 and mimeType is audio/mpeg for audio requests', () async {
      final scraper = UniversalScraper();
      final testUri = Uri.parse('https://example.com/some_song.mp4');

      final resolved = await scraper.resolve(testUri, DownloadKind.audio);
      expect(resolved.fileName.toLowerCase().endsWith('.mp3'), isTrue);
      expect(resolved.mimeType, 'audio/mpeg');
    });

    test('UnifiedDownloadEngine ensures MP3 download results in .mp3 file even if downloader returns .mp4', () async {
      // Create a fake downloaded MP4 file
      final mp4File = File('${tempDir.path}/downloaded_video.mp4');
      await mp4File.writeAsString('fake mp4 video stream bytes');

      final fakeResolver = _FakeVideoResolver(mp4File);
      final fakeDownloader = _FakeVideoDownloader(mp4File);

      final finalFile = await UnifiedDownloadEngine.instance.download(
        rawUrl: 'https://www.tiktok.com/@user/video/123456789',
        type: 'mp3',
        fallbackResolver: fakeResolver,
        fallbackDownloader: fakeDownloader,
      );

      // Final file MUST end with .mp3
      expect(finalFile.path.toLowerCase().endsWith('.mp3'), isTrue);
      expect(await finalFile.exists(), isTrue);
    });
  });
}
