import 'dart:io';

import 'package:vid_downloader_app/services/api_service.dart';

void main() async {
  final api = ApiService.instance;
  print('Base URL: ${api.baseUrl}');

  final testUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  print('Testing analyze for: $testUrl');

  try {
    final result = await api.analyze(url: testUrl, type: 'video');
    print('Analyze Success!');
    print('Title: ${result.title}');
    print('Filename: ${result.filename}');
    print('DownloadUrl: ${result.downloadUrl.substring(0, 100)}...');
    print('Headers: ${result.headers}');

    final tempFile = File('${Directory.systemTemp.path}/test_download.mp4');
    if (tempFile.existsSync()) tempFile.deleteSync();

    print('Testing downloadFile...');
    final file = await api.downloadFile(
      downloadUrl: result.downloadUrl,
      savePath: tempFile.path,
      headers: result.headers,
      onProgress: (received, total) {
        if (total > 0) {
          print(
            'Progress: ${(received / total * 100).toStringAsFixed(1)}% ($received / $total bytes)',
          );
        }
      },
    );

    print(
      'DownloadFile Success! File exists: ${file.existsSync()}, size: ${file.lengthSync()} bytes',
    );
    if (file.existsSync()) file.deleteSync();
  } catch (e, stack) {
    print('Test Failed with Error: $e');
    print('Stack: $stack');
  }
  exit(0);
}
