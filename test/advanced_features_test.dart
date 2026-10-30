import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/services/multi_threaded_downloader.dart';
import 'package:vid_downloader_app/services/private_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Advanced Download & Media Technologies Tests', () {
    test('VaultItem serialization and formatting works properly', () {
      final now = DateTime.now();
      final item = VaultItem(
        id: 'vault_1',
        originalName: 'private_video.mp4',
        encryptedFileName: 'x92f8k.dat',
        type: 'video',
        sizeInBytes: 15728640, // 15 MB
        addedAt: now,
      );

      expect(item.formattedSize, '15.0 MB');
      expect(item.isAudio, isFalse);

      final json = item.toJson();
      final restored = VaultItem.fromJson(json);

      expect(restored.id, 'vault_1');
      expect(restored.originalName, 'private_video.mp4');
      expect(restored.encryptedFileName, 'x92f8k.dat');
      expect(restored.sizeInBytes, 15728640);
    });

    test('MultiThreadedDownloader creates instance properly', () {
      final downloader = MultiThreadedDownloader(threadCount: 4);
      expect(downloader.threadCount, 4);
    });
  });
}
