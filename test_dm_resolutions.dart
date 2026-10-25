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
  debugPrint('Master M3U8: $streamUrl');

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
  debugPrint('Master status: ${m3u8Res.statusCode}');

  final lines = m3u8Res.data!.split('\n');
  final playlistMap = <int, String>{};
  int currentHeight = 0;

  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('#EXT-X-STREAM-INF:')) {
      final match = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(t);
      if (match != null) {
        currentHeight = int.tryParse(match.group(1)!) ?? 0;
      }
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      playlistMap[currentHeight] = t;
    }
  }

  debugPrint('Available resolutions: ${playlistMap.keys.toList()}');
}
