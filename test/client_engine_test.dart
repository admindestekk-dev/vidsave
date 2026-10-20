import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/client_media_resolver.dart';
import 'package:vid_downloader_app/ffmpeg_service.dart';
import 'package:vid_downloader_app/media_downloader.dart';

void main() {
  group('ClientMediaResolver Tests', () {
    late ClientMediaResolver resolver;

    setUp(() {
      resolver = ClientMediaResolver();
    });

    tearDown(() {
      resolver.dispose();
    });

    test('preview fallback on generic URL', () async {
      final preview = await resolver.preview(
        Uri.parse('https://example.com/test_video.mp4'),
        DownloadKind.video,
      );
      expect(preview.title, contains('test_video.mp4'));
      expect(preview.qualities.isNotEmpty, isTrue);
    });

    test('preview fallback on generic audio', () async {
      final preview = await resolver.preview(
        Uri.parse('https://example.com/song.mp3'),
        DownloadKind.audio,
      );
      expect(preview.qualities.any((q) => q.label.contains('MP3')), isTrue);
    });

    test('resolves generic URL directly with Chrome Mobile headers mask', () async {
      final uri = Uri.parse('https://example.com/direct_sample.mp4');
      final resolved = await resolver.resolve(uri, DownloadKind.video);
      expect(resolved.url, uri);
      expect(resolved.fileName.endsWith('.mp4'), isTrue);
      expect(
        resolved.downloadHeaders['User-Agent'],
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      );
      expect(resolved.downloadHeaders['Accept'], '*/*');
      expect(resolved.downloadHeaders['Accept-Language'], 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7');
      expect(resolved.downloadHeaders['Connection'], 'keep-alive');
    });
  });

  group('LocalFFmpegService Tests', () {
    test('isSupported check works in test environment', () {
      expect(LocalFFmpegService.instance.isSupported, isFalse);
    });

    test('mock conversion handles copy in test environment', () async {
      final tempDir = await Directory.systemTemp.createTemp('ffmpeg_test_');
      final inputFile = File('${tempDir.path}/input.mp4');
      final outputFile = File('${tempDir.path}/output.mp3');

      await inputFile.writeAsString('sample media content');

      final result = await LocalFFmpegService.instance.convertToMp3(
        inputFile: inputFile,
        outputFile: outputFile,
        startTime: 10,
        endTime: 30,
        audioEffect: 'nightcore',
      );

      expect(await result.exists(), isTrue);
      expect(await result.readAsString(), 'sample media content');

      await tempDir.delete(recursive: true);
    });
  });
}
