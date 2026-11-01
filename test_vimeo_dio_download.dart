import 'dart:io';

import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const downloadUrl =
      'https://vod-adaptive-ak.vimeocdn.com/exp=1792972573~acl=%2Fccfaa6de-0af0-44cb-a61a-8ecebadb6ad1%2Fpsid%3D8b013191c567051fb67785ff268b95288e5acf471792968973%2F%2A~hmac=31c230fa8debc45702f80c75b0739268077ff0266846f8fe17412d6e53d526f7/ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1/psid=8b013191c567051fb67785ff268b95288e5acf471792968973/v2/playlist/drm/cbcs,derivedv2,ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1,ed7ebc7c3bb14eeb8770374ffbd7512b/av/ccfaa6de/avf/5850de2a/media.m3u8?pathsig=8c953e4f~uYwIHHdZjPK02GB9KJvmyVFzaah54DMVqE11uVxEy7k&qsr=1&r=dXMtZWFzdDE%3D&st=video';
  final target = File('test_vimeo_downloaded.mp4');

  print('Calling dio.download on Vimeo media.m3u8...');
  try {
    await dio.download(
      downloadUrl,
      target.path,
      options: Options(
        headers: {
          'Referer': 'https://vimeo.com/76979871',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ),
    );
    print('Dio download finished. File size: ${await target.length()} bytes');
    final content = await target.readAsString();
    print('File contents preview (first 200 chars):');
    print(content.substring(0, 200));
  } catch (e) {
    print('Dio download error: $e');
  } finally {
    if (await target.exists()) {
      await target.delete();
    }
  }
}
