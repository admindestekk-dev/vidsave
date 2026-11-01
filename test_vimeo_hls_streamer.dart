import 'dart:io';

import 'package:dio/dio.dart';

Stream<List<int>> streamVimeoHls(String masterM3u8Url, Dio dio) async* {
  final masterUri = Uri.parse(masterM3u8Url);
  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Referer': 'https://player.vimeo.com/',
    'Origin': 'https://player.vimeo.com',
  };

  final masterRes = await dio.get<String>(
    masterM3u8Url,
    options: Options(headers: headers),
  );
  final masterLines = (masterRes.data ?? '').split('\n');

  // 1. En yüksek kaliteli alt playlist'i seç
  String? chosenPlaylistUrl;
  for (final line in masterLines) {
    final t = line.trim();
    if (t.startsWith('http')) {
      chosenPlaylistUrl = t;
      if (t.contains('1080') || t.contains('720')) break;
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      chosenPlaylistUrl = masterUri.resolve(t).toString();
      if (t.contains('1080') || t.contains('720')) break;
    }
  }

  if (chosenPlaylistUrl == null) {
    throw Exception('Vimeo video oynatma listesi bulunamadı.');
  }

  final subUri = Uri.parse(chosenPlaylistUrl);
  final subRes = await dio.get<String>(
    chosenPlaylistUrl,
    options: Options(headers: headers),
  );
  final subLines = (subRes.data ?? '').split('\n');

  String? initUriStr;
  final segmentUris = <String>[];

  for (final line in subLines) {
    final t = line.trim();
    if (t.startsWith('#EXT-X-MAP:URI="')) {
      final end = t.indexOf('"', 16);
      if (end > 16) {
        initUriStr = t.substring(16, end);
      }
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      segmentUris.add(t);
    }
  }

  // 2. Fragmented MP4 (fMP4) Init Segment'ini akışa gönder
  if (initUriStr != null) {
    final initFull = subUri.resolve(initUriStr).toString();
    final initRes = await dio.get<List<int>>(
      initFull,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    if (initRes.data != null && initRes.data!.isNotEmpty) {
      yield initRes.data!;
    }
  }

  // 3. Sırasıyla tüm video segmentlerini çek ve kesintisiz akıt
  for (final seg in segmentUris) {
    final segFull = subUri.resolve(seg).toString();
    final segRes = await dio.get<List<int>>(
      segFull,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    if (segRes.data != null && segRes.data!.isNotEmpty) {
      yield segRes.data!;
    }
  }
}

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://player.vimeo.com/video/76979871';

  final res = await dio.get<String>(
    vimeoUrl,
    options: Options(headers: {'Referer': 'https://vimeo.com/'}),
  );

  final html = res.data ?? '';
  final hlsMatch = RegExp(
    r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"',
  ).firstMatch(html);
  var rawHls = hlsMatch?.group(1);
  rawHls = rawHls!
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\u003d', '=');
  print('Resolved rawHls: $rawHls');

  final file = File('vimeo_test_out.mp4');
  final sink = file.openWrite();
  var chunksCount = 0;
  var totalBytes = 0;

  // Stream first 5 segments and write to file
  await for (final chunk in streamVimeoHls(rawHls, dio).take(5)) {
    sink.add(chunk);
    chunksCount++;
    totalBytes += chunk.length;
    print('Chunk $chunksCount: ${chunk.length} bytes (Total: $totalBytes)');
  }

  await sink.flush();
  await sink.close();

  print('Finished! File size on disk: ${await file.length()} bytes');
  final bytes = await file.readAsBytes();
  if (bytes.sublist(4, 8).map((b) => String.fromCharCode(b)).join() == 'ftyp') {
    print('SUCCESS! Valid MP4 header verified!');
  }

  await file.delete();
}
