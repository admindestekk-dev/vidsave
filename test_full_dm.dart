import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final metaRes = await dio.get<Map<String, dynamic>>(
    'https://www.dailymotion.com/player/metadata/video/x9t3htk',
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );
  final streamUrl = metaRes.data?['qualities']?['auto']?.first['url'];
  final m3u8Res = await dio.get<String>(
    streamUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.dailymotion.com/',
      },
    ),
  );
  final lines = m3u8Res.data!.split('\n');
  String? subUrl;
  for (final l in lines) {
    if (l.trim().startsWith('http')) {
      subUrl = l.trim();
      if (l.contains('480') || l.contains('720')) break;
    }
  }

  final subRes = await dio.get<String>(
    subUrl!,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.dailymotion.com/',
      },
    ),
  );
  final baseUri = Uri.parse(subUrl);

  final subLines = subRes.data!.split('\n');
  String? initUriStr;
  final segmentUris = <String>[];

  for (final l in subLines) {
    final t = l.trim();
    if (t.startsWith('#EXT-X-MAP:URI="')) {
      final end = t.indexOf('"', 16);
      initUriStr = t.substring(16, end);
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      segmentUris.add(t);
    }
  }

  final totalSegments = segmentUris.length;
  debugPrint('Total segments to download: $totalSegments');

  final outputFile = File('dm_full_video.mp4');
  final sink = outputFile.openWrite();

  if (initUriStr != null) {
    final initFull = baseUri.resolve(initUriStr).toString();
    final initRes = await dio.get<List<int>>(
      initFull,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.dailymotion.com/',
        },
      ),
    );
    sink.add(initRes.data!);
  }

  var downloadedCount = 0;
  for (final seg in segmentUris) {
    final segFull = baseUri.resolve(seg).toString();
    final segRes = await dio.get<List<int>>(
      segFull,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.dailymotion.com/',
        },
      ),
    );
    sink.add(segRes.data!);
    downloadedCount++;
    if (downloadedCount % 5 == 0 || downloadedCount == totalSegments) {
      debugPrint('Progress: $downloadedCount / $totalSegments');
    }
  }

  await sink.flush();
  await sink.close();

  final fileLen = await outputFile.length();
  debugPrint('SUCCESS: Full MP4 file written! Size: $fileLen bytes');
}
