import 'dart:io';

import 'package:flutter/services.dart';

class AndroidVideoWatermarker {
  static const MethodChannel _channel = MethodChannel(
    'vidsave/video_watermark',
  );

  static Future<File> apply(File source) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Video filigranı şu anda Android için kullanılabilir.',
      );
    }
    if (!await source.exists()) {
      throw FileSystemException(
        'Filigran uygulanacak video bulunamadı.',
        source.path,
      );
    }

    final outputPath = await _channel.invokeMethod<String>('watermarkVideo', {
      'sourcePath': source.path,
    });
    if (outputPath == null || outputPath.isEmpty) {
      throw StateError('Android filigran işlemi çıktı dosyası döndürmedi.');
    }

    final output = File(outputPath);
    if (!await output.exists()) {
      throw FileSystemException('Filigranlı video oluşturulamadı.', outputPath);
    }
    return output;
  }
}
