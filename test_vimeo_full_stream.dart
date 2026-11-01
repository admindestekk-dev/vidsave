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
  var hlsUrl = cdnObj['url']?.toString();

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

  final videoList = (mjData['video'] as List<dynamic>)
    ..sort(
      (a, b) =>
          ((b['height'] as int?) ?? 0).compareTo((a['height'] as int?) ?? 0),
    );
  final bestVideo = videoList.first as Map<String, dynamic>;
  final videoBaseUrl = bestVideo['base_url'].toString();
  final videoTargetBaseUri = baseUri.resolve(videoBaseUrl);

  final audioList = mjData['audio'] as List<dynamic>;
  final bestAudio = audioList.first as Map<String, dynamic>;
  final audioBaseUrl = bestAudio['base_url'].toString();
  final audioTargetBaseUri = baseUri.resolve(audioBaseUrl);

  print('Video base: $videoTargetBaseUri');
  print('Audio base: $audioTargetBaseUri');
  print('Video segments: ${(bestVideo['segments'] as List).length}');
  print('Audio segments: ${(bestAudio['segments'] as List).length}');

  // Download video file
  final vFile = File('v_temp.mp4');
  final vSink = vFile.openWrite();
  final vInitB64 = bestVideo['init_segment'] as String?;
  if (vInitB64 != null) vSink.add(base64Decode(vInitB64));
  for (final s in (bestVideo['segments'] as List)) {
    final sUrl = videoTargetBaseUri.resolve(s['url'].toString()).toString();
    final sRes = await dio.get<List<int>>(
      sUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Referer': 'https://player.vimeo.com/'},
      ),
    );
    vSink.add(sRes.data!);
  }
  await vSink.flush();
  await vSink.close();
  print('Video stream size: ${await vFile.length()}');

  // Download audio file
  final aFile = File('a_temp.m4a');
  final aSink = aFile.openWrite();
  final aInitB64 = bestAudio['init_segment'] as String?;
  if (aInitB64 != null) aSink.add(base64Decode(aInitB64));
  for (final s in (bestAudio['segments'] as List)) {
    final sUrl = audioTargetBaseUri.resolve(s['url'].toString()).toString();
    final sRes = await dio.get<List<int>>(
      sUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Referer': 'https://player.vimeo.com/'},
      ),
    );
    aSink.add(sRes.data!);
  }
  await aSink.flush();
  await aSink.close();
  print('Audio stream size: ${await aFile.length()}');

  // Now test ffmpeg merge!
  final proc = await Process.run('ffmpeg', [
    '-y',
    '-i',
    vFile.path,
    '-i',
    aFile.path,
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    'vimeo_merged_final.mp4',
  ]);
  print('FFmpeg exit code: ${proc.exitCode}');
  final merged = File('vimeo_merged_final.mp4');
  print(
    'Merged final file exists: ${await merged.exists()}, size: ${await merged.length()} bytes',
  );

  // Cleanup
  await vFile.delete();
  await aFile.delete();
  await merged.delete();
}
