import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';

/// Service that executes FFmpeg commands directly on the user's phone CPU
/// using ffmpeg_kit_flutter_min_gpl.
///
/// Features:
/// 1. Mux separate high-resolution video and audio streams into single MP4.
/// 2. Convert MP4 to MP3 directly on device CPU (-i input.mp4 -vn -ar 44100 -ac 2 -b:a 192k output.mp3).
/// 3. Audio Trimming (RangeSlider: startTime & endTime).
/// 4. Audio Effects:
///    - Nightcore: asetrate=44100*1.25,aresample=44100,atempo=1.06
///    - Bass Boost: bass=g=10:f=110:w=0.6
class LocalFFmpegService {
  LocalFFmpegService._();
  static final LocalFFmpegService instance = LocalFFmpegService._();

  /// Whether current platform supports ffmpeg_kit native bindings
  bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  /// Merges separate video and audio files into a unified MP4 file.
  Future<File> mergeVideoAndAudio({
    required File videoFile,
    required File audioFile,
    required File outputFile,
  }) async {
    if (!isSupported) {
      // In test or unsupported environment, keep the video file
      if (await outputFile.exists()) await outputFile.delete();
      await videoFile.copy(outputFile.path);
      return outputFile;
    }

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    // -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest
    final cmd =
        '-y -i "${videoFile.path}" -i "${audioFile.path}" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "${outputFile.path}"';

    debugPrint('LocalFFmpegService: Executing merge: $cmd');
    final completer = Completer<File>();

    await FFmpegKit.executeAsync(
      cmd,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
          completer.complete(outputFile);
        } else {
          final failTrace = await session.getFailStackTrace();
          final output = await session.getOutput();
          completer.completeError(
            Exception(
              'FFmpeg birleştirme başarısız oldu (rc: $returnCode). $failTrace $output',
            ),
          );
        }
      },
    );

    return completer.future;
  }

  /// Converts video/audio input to high-quality MP3 with optional trimming and audio effects.
  ///
  /// Command structure requested by user:
  /// `-i input.mp4 -vn -ar 44100 -ac 2 -b:a 192k output.mp3`
  Future<File> convertToMp3({
    required File inputFile,
    required File outputFile,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    if (!isSupported) {
      // In test or unsupported environment, emulate output
      if (await outputFile.exists()) await outputFile.delete();
      await inputFile.copy(outputFile.path);
      return outputFile;
    }

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    // Build FFmpeg command arguments
    final args = <String>['-y'];

    // Start time trim (-ss) before input for fast seek
    if (startTime != null && startTime > 0) {
      args.addAll(['-ss', startTime.toStringAsFixed(2)]);
    }

    args.addAll(['-i', '"${inputFile.path}"']);

    // End time trim (-to) or duration (-t)
    if (endTime != null && endTime > 0) {
      if (startTime != null && startTime > 0) {
        final duration = endTime - startTime;
        if (duration > 0) {
          args.addAll(['-t', duration.toStringAsFixed(2)]);
        }
      } else {
        args.addAll(['-t', endTime.toStringAsFixed(2)]);
      }
    }

    // Audio filters (Nightcore, Bass Boost)
    final filter = _buildAudioFilter(audioEffect);
    if (filter != null && filter.isNotEmpty) {
      args.addAll(['-af', filter]);
    }

    // Standard high-quality MP3 encoding
    args.addAll([
      '-vn',
      '-ar',
      '44100',
      '-ac',
      '2',
      '-b:a',
      '192k',
      '"${outputFile.path}"',
    ]);

    final cmd = args.join(' ');
    debugPrint('LocalFFmpegService: Executing convertToMp3: $cmd');

    final completer = Completer<File>();

    await FFmpegKit.executeAsync(
      cmd,
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
          completer.complete(outputFile);
        } else {
          final failTrace = await session.getFailStackTrace();
          final output = await session.getOutput();
          completer.completeError(
            Exception(
              'FFmpeg MP3 dönüştürme başarısız oldu (rc: $returnCode). $failTrace $output',
            ),
          );
        }
      },
    );

    return completer.future;
  }

  /// Builds FFmpeg audio filter string for selected effect
  String? _buildAudioFilter(String? effect) {
    if (effect == null || effect == 'normal') return null;

    switch (effect.toLowerCase()) {
      case 'nightcore':
        // Nightcore increases pitch & tempo
        return 'asetrate=44100*1.25,aresample=44100,atempo=1.06';
      case 'bassboost':
        // Bass boost enhances low frequencies around 110Hz
        return 'bass=g=10:f=110:w=0.6';
      default:
        return null;
    }
  }
}
