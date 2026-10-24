import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/download_exception_handler.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/remote_config_service.dart';

void main() {
  group('MediaDownloader 3 Aşamalı Güvenlik Kalkanı Testleri', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'downloader_security_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      RemoteConfigService.instance.clearOverrides();
    });

    test('1. Aşama: HEAD isteğinde text/html veya application/json döndüğünde indirmeyi abort eder ve MediaVerificationException fırlatır', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            if (opts.method == 'HEAD') {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['text/html; charset=utf-8'],
                    'content-length': ['15000'],
                  }),
                ),
              );
            } else {
              handler.reject(
                DioException(
                  requestOptions: opts,
                  error: 'İndirme başlamamalıydı!',
                ),
              );
            }
          },
        ),
      );

      final downloader = MediaDownloader(
        dioClient: dio,
        directoryProvider: () async => tempDir,
      );

      final media = ResolvedMedia(
        url: Uri.parse('https://example.com/fake_html_stream.mp4'),
        fileName: 'fake_test.mp4',
      );

      expect(
        () => downloader.download(media),
        throwsA(
          isA<MediaVerificationException>().having(
            (e) => e.isBotBlock,
            'isBotBlock',
            isTrue,
          ),
        ),
      );

      // Cihaz hafızasına sahte dosya yazılmamalı
      final files = tempDir.listSync();
      expect(files.isEmpty, isTrue);
    });

    test('2. Aşama: HEAD isteğinde Content-Length 1 MB altı (<1024*1024) ise indirmeyi durdurur ve uyarı mesajı üretir', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            if (opts.method == 'HEAD') {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['video/mp4'],
                    'content-length': ['512000'], // 500 KB (< 1 MB)
                  }),
                ),
              );
            } else {
              handler.reject(
                DioException(
                  requestOptions: opts,
                  error: 'İndirme başlamamalıydı!',
                ),
              );
            }
          },
        ),
      );

      final downloader = MediaDownloader(
        dioClient: dio,
        directoryProvider: () async => tempDir,
      );

      final media = ResolvedMedia(
        url: Uri.parse('https://example.com/small_video.mp4'),
        fileName: 'small_test.mp4',
      );

      try {
        await downloader.download(media);
        fail('Hata fırlatılmalıydı');
      } catch (e) {
        expect(e, isA<MediaVerificationException>());
        final msg = DownloadExceptionHandler.getFriendlyMessage(e, null);
        expect(
          msg,
          contains(
            'Medya kaynağı çok küçük veya geçersiz, lütfen linki yenileyip tekrar deneyin',
          ),
        );
      }

      // Dosya diske yazılmamalı
      expect(tempDir.listSync().isEmpty, isTrue);
    });

    test('1. ve 2. Aşama Geçerli: Gerçek video dosyası (> 1 MB, video/mp4) başarıyla indirilir', () async {
      final dio = Dio();
      final targetFile = File(
        '${tempDir.path}${Platform.pathSeparator}valid_test.mp4',
      );

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) {
            if (opts.method == 'HEAD') {
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  headers: Headers.fromMap({
                    'content-type': ['video/mp4'],
                    'content-length': ['2097152'], // 2 MB (> 1 MB)
                  }),
                ),
              );
            } else {
              targetFile.writeAsBytesSync(List.filled(2 * 1024 * 1024, 65));
              handler.resolve(
                Response(
                  requestOptions: opts,
                  statusCode: 200,
                  data: ResponseBody.fromBytes(
                    List.filled(2 * 1024 * 1024, 65),
                    200,
                    headers: {
                      Headers.contentTypeHeader: ['video/mp4'],
                    },
                  ),
                ),
              );
            }
          },
        ),
      );

      final downloader = MediaDownloader(
        dioClient: dio,
        directoryProvider: () async => tempDir,
      );

      final media = ResolvedMedia(
        url: Uri.parse('https://example.com/real_hd_video.mp4'),
        fileName: 'valid_test.mp4',
      );

      final downloadedFile = await downloader.download(media);
      expect(await downloadedFile.exists(), isTrue);
      expect(
        await downloadedFile.length(),
        greaterThanOrEqualTo(kMinValidMediaBytes),
      );
    });
  });
}
