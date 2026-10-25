import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  try {
    final metaRes = await dio.get<Map<String, dynamic>>(
      'https://www.dailymotion.com/player/metadata/video/x9t3htk',
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ),
    );
    debugPrint('Status: ${metaRes.statusCode}');
    final qualities = metaRes.data?['qualities'];
    debugPrint('Qualities keys: ${qualities?.keys}');
    if (qualities is Map) {
      final auto = qualities['auto'];
      debugPrint('Auto type: ${auto.runtimeType}');
      if (auto is List && auto.isNotEmpty) {
        final streamUrl = auto.first['url'];
        debugPrint('Stream URL: $streamUrl');

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
        debugPrint('M3U8 Status: ${m3u8Res.statusCode}');
        debugPrint('M3U8 Body:\n${m3u8Res.data?.substring(0, 500)}');
      }
    }
  } catch (e) {
    debugPrint('Error: $e');
  }
}
