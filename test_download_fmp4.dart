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
  // 720p veya ilk sub playlist'i al
  final lines = m3u8Res.data!.split('\n');
  String? subUrl;
  for (final l in lines) {
    if (l.trim().startsWith('http')) {
      subUrl = l.trim();
      if (l.contains('720') || l.contains('hd')) break;
    }
  }
  debugPrint('Sub M3U8: $subUrl');

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

  // init.mp4 ve ilk 3 segmenti indirip birleştir
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
  debugPrint('Init: $initUriStr, Segments count: ${segmentUris.length}');

  final outputFile = File('test_merged.mp4');
  final sink = outputFile.openWrite();

  if (initUriStr != null) {
    final initFull = baseUri.resolve(initUriStr).toString();
    final initBytes = (await dio.get<List<int>>(
      initFull,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.dailymotion.com/',
        },
      ),
    )).data!;
    sink.add(initBytes);
    debugPrint('Init bytes written: ${initBytes.length}');
  }

  // İlk 5 segmenti yaz
  for (int i = 0; i < 5 && i < segmentUris.length; i++) {
    final segFull = baseUri.resolve(segmentUris[i]).toString();
    final segBytes = (await dio.get<List<int>>(
      segFull,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.dailymotion.com/',
        },
      ),
    )).data!;
    sink.add(segBytes);
    debugPrint('Segment $i written: ${segBytes.length}');
  }
  await sink.flush();
  await sink.close();

  debugPrint('Total file size: ${await outputFile.length()} bytes');
}
