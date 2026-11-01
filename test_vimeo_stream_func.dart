import 'dart:convert';

import 'package:dio/dio.dart';

Stream<List<int>> streamVimeoFast(String html, Dio dio) async* {
  final startIdx = html.indexOf('window.playerConfig = {');
  if (startIdx == -1) return;
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
  if (hlsUrl == null) return;

  var masterJsonUrl = hlsUrl;
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

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Referer': 'https://player.vimeo.com/',
  };

  final mjRes = await dio.get<Map<String, dynamic>>(
    masterJsonUrl,
    options: Options(headers: headers),
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

  final vInitB64 = bestVideo['init_segment'] as String?;
  if (vInitB64 != null) {
    yield base64Decode(vInitB64);
  }

  final segments = bestVideo['segments'] as List<dynamic>;
  for (final s in segments) {
    final sUrl = videoTargetBaseUri.resolve(s['url'].toString()).toString();
    final sRes = await dio.get<List<int>>(
      sUrl,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    if (sRes.data != null && sRes.data!.isNotEmpty) {
      yield sRes.data!;
    }
  }
}

void main() async {
  final dio = Dio();
  final res = await dio.get<String>(
    'https://player.vimeo.com/video/76979871',
    options: Options(headers: {'Referer': 'https://vimeo.com/'}),
  );

  var totalReceived = 0;
  await for (final chunk in streamVimeoFast(res.data!, dio).take(5)) {
    totalReceived += chunk.length;
    print('Yielded chunk: ${chunk.length} bytes (Total: $totalReceived)');
  }
  print('Stream test passed!');
}
