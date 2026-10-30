import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_dio.dart';

/// VidSave Çoklu Parçacıklı İndirme Hızlandırıcı (Multi-threaded Downloader)
///
/// IDM (Internet Download Manager) mimarisi ile çalışır:
/// 1. Sunucuya `HEAD` isteği atarak dosya boyutunu (`Content-Length`) ve
///    `Accept-Ranges: bytes` desteğini kontrol eder.
/// 2. Eğer `Range` destekleniyorsa ve dosya yeterince büyükse (>= 2 MB),
///    dosyayı 4 eşzamanlı parçaya böler (Part 0..3).
/// 3. Her bir iş parçacığı `Range: bytes=start-end` başlığıyla eşzamanlı indirir
///    (ağ bant genişliğini 4 katına kadar doygunlaştırır).
/// 4. Tüm parçalar tamamlandığında disk düzeyinde sıralı `RandomAccessFile`
///    stream'i ile tek bir kararlı ve sağlam hedef dosyada birleştirilir.
/// 5. Range desteklenmiyorsa veya sunucu hata verirse pürüzsüzce tek parça indirmeye fallback yapar.
class MultiThreadedDownloader {
  MultiThreadedDownloader({Dio? dioClient, this.threadCount = 4})
    : _dio = dioClient ?? AppDio.createClient();

  final Dio _dio;
  final int threadCount;

  /// Çoklu parçacıklı veya tek parçacıklı hızlandırılmış indirmeyi yönetir.
  Future<File> downloadWithAccelerator({
    required String url,
    required String savePath,
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final targetFile = File(savePath);
    final parentDir = targetFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    // 1. Sunucu özelliklerini ve dosya boyutunu analiz et (HEAD isteği)
    int? contentLength;
    bool supportsRange = false;

    try {
      final headResponse = await _dio.head<dynamic>(
        url,
        options: Options(
          headers: headers,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
        cancelToken: cancelToken,
      );

      final acceptRanges = headResponse.headers.value('accept-ranges');
      final lengthHeader = headResponse.headers.value('content-length');
      if (lengthHeader != null) {
        contentLength = int.tryParse(lengthHeader);
      }
      supportsRange =
          acceptRanges?.toLowerCase() == 'bytes' &&
          contentLength != null &&
          contentLength > (2 * 1024 * 1024); // 2 MB'tan büyükse
    } catch (e) {
      debugPrint('MultiThreadedDownloader HEAD analizi fallback: $e');
      supportsRange = false;
    }

    // Range desteklenmiyorsa veya boyut bilinemiyorsa standart tek parça akışla indir
    if (!supportsRange || contentLength == null || contentLength <= 0) {
      await _dio.download(
        url,
        savePath,
        options: Options(
          headers: headers,
          followRedirects: true,
          maxRedirects: 10,
        ),
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
      );
      return targetFile;
    }

    // 2. Çoklu parçacıklı (Multi-threaded) İndirme Mimarisi (4 Eşzamanlı Parça)
    final totalSize = contentLength;
    final int parts = threadCount.clamp(2, 8);
    final chunkSize = (totalSize / parts).ceil();

    final List<File> chunkFiles = [];
    final List<int> receivedPerPart = List<int>.filled(parts, 0);

    try {
      final futures = <Future<void>>[];

      for (int i = 0; i < parts; i++) {
        final startByte = i * chunkSize;
        final endByte = (i == parts - 1)
            ? totalSize - 1
            : (startByte + chunkSize - 1);

        final chunkFilePath = '$savePath.part_$i';
        final chunkFile = File(chunkFilePath);
        chunkFiles.add(chunkFile);

        final partHeaders = Map<String, String>.from(headers ?? {});
        partHeaders['Range'] = 'bytes=$startByte-$endByte';

        final partFuture = () async {
          await _dio.download(
            url,
            chunkFilePath,
            options: Options(headers: partHeaders, followRedirects: true),
            onReceiveProgress: (rec, _) {
              receivedPerPart[i] = rec;
              if (onProgress != null) {
                final currentTotal = receivedPerPart.fold<int>(
                  0,
                  (sum, val) => sum + val,
                );
                onProgress(currentTotal, totalSize);
              }
            },
            cancelToken: cancelToken,
            deleteOnError: true,
          );
        }();

        futures.add(partFuture);
      }

      // Tüm parçaların eşzamanlı inmesini bekle
      await Future.wait(futures);

      // 3. Parçaları Sıralı Olarak Tek Dosyada Birleştir (Merge)
      final outputSink = targetFile.openSync(mode: FileMode.write);
      try {
        for (final chunk in chunkFiles) {
          if (chunk.existsSync()) {
            final bytes = chunk.readAsBytesSync();
            outputSink.writeFromSync(bytes);
            chunk.deleteSync(); // Geçici parçayı sil
          }
        }
      } finally {
        outputSink.closeSync();
      }

      onProgress?.call(totalSize, totalSize);
      return targetFile;
    } catch (e) {
      debugPrint('MultiThreadedDownloader hata: $e. Temizlik yapılıyor...');
      // Hata durumunda geçici parçaları temizle
      for (final chunk in chunkFiles) {
        if (chunk.existsSync()) {
          try {
            chunk.deleteSync();
          } catch (_) {}
        }
      }
      rethrow;
    }
  }
}
