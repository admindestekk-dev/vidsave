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
    final qualities = metaRes.data?['qualities'];
    final auto = qualities?['auto'];
    final streamUrl = auto?.first['url'];
    debugPrint('Master m3u8 URL: $streamUrl');

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
    final m3u8Body = m3u8Res.data!;
    debugPrint('--- Master M3U8 Content ---');
    debugPrint(m3u8Body);

    // İlk alt playlist URL'sini bul
    final lines = m3u8Body.split('\n');
    String? subPlaylistUrl;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        subPlaylistUrl = trimmed.startsWith('http')
            ? trimmed
            : Uri.parse(streamUrl).resolve(trimmed).toString();
        break;
      }
    }

    debugPrint('\nSub Playlist URL: $subPlaylistUrl');
    if (subPlaylistUrl != null) {
      final subRes = await dio.get<String>(
        subPlaylistUrl,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.dailymotion.com/',
          },
        ),
      );
      debugPrint('--- Sub M3U8 Content (First 15 lines) ---');
      debugPrint(subRes.data!.split('\n').take(15).join('\n'));
    }
  } catch (e) {
    debugPrint('Error: $e');
  }
}
