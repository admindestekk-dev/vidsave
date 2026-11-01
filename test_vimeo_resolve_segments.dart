import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final subUri = Uri.parse(
    'https://vod-adaptive-ak.vimeocdn.com/exp=1792974529~acl=%2Fccfaa6de-0af0-44cb-a61a-8ecebadb6ad1%2Fpsid%3Df5c0ff0465b62acdb810e0ec1a3f3fc995b7cdf71792970929%2F%2A~hmac=837d22214d6123483e07b45791c3d41334ac80ccc041076a1b04c83c5ebe9ea7/ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1/psid=f5c0ff0465b62acdb810e0ec1a3f3fc995b7cdf71792970929/v2/playlist/drm/cbcs,derivedv2,ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1,ed7ebc7c3bb14eeb8770374ffbd7512b/av/ccfaa6de/avf/a565ff5d/media.m3u8?pathsig=8c953e4f~3MfE5nWhkitmQK8-5ISfshhGdIP3w1rfQuZq7Ab9xz0&qsr=1&r=dXMtZWFzdDE%3D&st=video',
  );
  const initRel =
      '../../../../../../../drm/cbcs,derivedv2,ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1,ed7ebc7c3bb14eeb8770374ffbd7512b/remux/avf/a565ff5d-0047-429c-964e-76e06e192b45/segment.mp4?pathsig=8c953e4f~xMCeFj_HSRK4gFAkgI3AaLPeRrw3XRrh4kbOADzDWS0&r=dXMtY2VudHJhbDE%3D&sid=0&st=video';
  const seg1Rel =
      '../../../../../../../drm/cbcs,derivedv2,ccfaa6de-0af0-44cb-a61a-8ecebadb6ad1,ed7ebc7c3bb14eeb8770374ffbd7512b/remux/avf/a565ff5d-0047-429c-964e-76e06e192b45/segment.m4s?pathsig=8c953e4f~3ftmEju2L2fgbcoVAq3KbyTwrIgYec7B2XTZ7u95tPk&r=dXMtY2VudHJhbDE%3D&sid=1&st=video';

  final initFull = subUri.resolve(initRel).toString();
  print('initFull: $initFull');

  final initRes = await dio.get<List<int>>(
    initFull,
    options: Options(
      responseType: ResponseType.bytes,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );
  print('Init status: ${initRes.statusCode}, bytes: ${initRes.data?.length}');

  final seg1Full = subUri.resolve(seg1Rel).toString();
  final seg1Res = await dio.get<List<int>>(
    seg1Full,
    options: Options(
      responseType: ResponseType.bytes,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );
  print('Seg 1 status: ${seg1Res.statusCode}, bytes: ${seg1Res.data?.length}');
}
