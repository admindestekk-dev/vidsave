import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://player.vimeo.com/video/76979871';

  final res = await dio.get<String>(
    vimeoUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = res.data ?? '';
  final startIdx = html.indexOf('window.playerConfig = {');
  final jsonStart = startIdx + 'window.playerConfig = '.length;
  final endIdx = html.indexOf('</script>', jsonStart);
  var jsonStr = html
      .substring(jsonStart, endIdx != -1 ? endIdx : html.length)
      .trim();
  if (jsonStr.endsWith(';'))
    jsonStr = jsonStr.substring(0, jsonStr.length - 1).trim();

  final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
  final request = jsonMap['request'] as Map<String, dynamic>?;
  final files = request?['files'] as Map<String, dynamic>?;
  final cdns = files?['hls']?['cdns'] as Map<String, dynamic>?;
  final defaultCdn =
      files?['hls']?['default_cdn']?.toString() ?? cdns?.keys.first;
  final cdnObj = cdns?[defaultCdn] ?? cdns?.values.first;
  final hlsUrl = cdnObj['url']?.toString();

  var masterJsonUrl = hlsUrl!;
  if (masterJsonUrl.contains('/playlist.m3u8')) {
    masterJsonUrl = masterJsonUrl.replaceAll(
      '/playlist.m3u8',
      '/master.json?base64_init=1',
    );
  } else if (masterJsonUrl.contains('/master.m3u8')) {
    masterJsonUrl = masterJsonUrl.replaceAll(
      '/master.m3u8',
      '/master.json?base64_init=1',
    );
  }

  final mjRes = await dio.get<Map<String, dynamic>>(
    masterJsonUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );

  final mjData = mjRes.data!;
  final baseUrlStr = mjData['base_url'].toString();
  final masterUri = Uri.parse(masterJsonUrl);
  final baseUri = masterUri.resolve(baseUrlStr);

  final audioList = mjData['audio'] as List<dynamic>;
  final bestAudio = audioList.first as Map<String, dynamic>;
  final audioBaseUrl = bestAudio['base_url'].toString();
  final audioTargetBaseUri = baseUri.resolve(audioBaseUrl);

  print(
    'Audio codec: ${bestAudio['codecs']}, bitrate: ${bestAudio['bitrate']}',
  );
  final initAudioB64 = bestAudio['init_segment'] as String?;
  final initAudioBytes = initAudioB64 != null
      ? base64Decode(initAudioB64)
      : null;

  final segments = bestAudio['segments'] as List<dynamic>;
  print('Audio segments count: ${segments.length}');

  final file = File('vimeo_test_audio.m4a');
  final sink = file.openWrite();
  if (initAudioBytes != null) {
    sink.add(initAudioBytes);
  }

  for (int i = 0; i < 3 && i < segments.length; i++) {
    final segUrl = segments[i]['url'].toString();
    final fullSegUri = audioTargetBaseUri.resolve(segUrl);
    final segRes = await dio.get<List<int>>(
      fullSegUri.toString(),
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://player.vimeo.com/',
        },
      ),
    );
    sink.add(segRes.data!);
  }

  await sink.flush();
  await sink.close();

  print('Audio file created! Size: ${await file.length()} bytes');
  final checkBytes = await file.readAsBytes();
  if (checkBytes.sublist(4, 8).map((b) => String.fromCharCode(b)).join() ==
      'ftyp') {
    print('VERIFIED VALID M4A / MP4 AUDIO CONTAINER HEADER!');
  }
}
