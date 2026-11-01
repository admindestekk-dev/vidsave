import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const subPlaylistUrl =
      'https://vod-adaptive-ak.vimeocdn.com/exp=1792973681~acl=%2Fccfaa6de-0af0-44cb-a61a-8ecebadb6ad1%2Fpsid%3D406b5491e24ae1661dbb8816eed09144f08664891792970081%2F%2A~hmac=67685cd8c84a5e13de8ef024c3bfebcf45205defdcc558782e5ba60441b47d4a/ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1/psid=406b5491e24ae1661dbb8816eed09144f08664891792970081/v2/playlist/drm/cbcs,derivedv2,ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1,ed7ebc7c3bb14eeb8770374ffbd7512b/av/ccfaa6de/avf/5850de2a/media.m3u8?pathsig=8c953e4f~uYwIHHdZjPK02GB9KJvmyVFzaah54DMVqE11uVxEy7k&qsr=1&r=dXMtZWFzdDE%3D&st=video';

  final subRes = await dio.get<String>(
    subPlaylistUrl,
    options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final subLines = (subRes.data ?? '').split('\n');
  print('Sub lines count: ${subLines.length}');
  for (int i = 0; i < 20; i++) {
    print(subLines[i]);
  }
}
