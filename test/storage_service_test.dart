import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/download_item_model.dart';
import 'package:vid_downloader_app/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.clearAll();
  });

  group('DownloadItemModel', () {
    test('toJson and fromJson work correctly', () {
      final now = DateTime.now();
      final model = DownloadItemModel(
        id: 'test_123',
        name: 'sarki.mp3',
        type: 'audio',
        sizeInBytes: 5242880, // 5 MB
        filePath: '/storage/emulated/0/Download/sarki.mp3',
        downloadedAt: now,
        sourceUrl: 'https://youtube.com/watch?v=abc',
      );

      final json = model.toJson();
      final restored = DownloadItemModel.fromJson(json);

      expect(restored.id, 'test_123');
      expect(restored.name, 'sarki.mp3');
      expect(restored.type, 'audio');
      expect(restored.isAudio, isTrue);
      expect(restored.sizeInBytes, 5242880);
      expect(restored.formattedSize, '5.0 MB');
      expect(restored.filePath, '/storage/emulated/0/Download/sarki.mp3');
      expect(restored.sourceUrl, 'https://youtube.com/watch?v=abc');
      expect(restored.downloadedAt.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch);
    });

    test('formattedSize handles various sizes', () {
      final kbItem = DownloadItemModel(
        id: '1',
        name: 'test.mp4',
        type: 'video',
        sizeInBytes: 2048,
        filePath: '/test.mp4',
        downloadedAt: DateTime.now(),
      );
      expect(kbItem.formattedSize, '2.0 KB');
      expect(kbItem.isAudio, isFalse);

      final zeroItem = DownloadItemModel(
        id: '2',
        name: 'test.mp4',
        type: 'video',
        sizeInBytes: 0,
        filePath: '/test.mp4',
        downloadedAt: DateTime.now(),
      );
      expect(zeroItem.formattedSize, '0 B');
    });
  });

  group('StorageService', () {
    test('addItem saves to storage and notifies listeners', () async {
      final item = DownloadItemModel(
        id: 'id_1',
        name: 'video_1.mp4',
        type: 'video',
        sizeInBytes: 10485760,
        filePath: '/downloads/video_1.mp4',
        downloadedAt: DateTime.now(),
      );

      bool notified = false;
      void listener() {
        notified = true;
      }

      StorageService.downloadsNotifier.addListener(listener);

      await StorageService.addItem(item);

      expect(notified, isTrue);
      expect(StorageService.downloadsNotifier.value.length, 1);
      expect(StorageService.downloadsNotifier.value.first.id, 'id_1');

      final itemsFromDb = await StorageService.getItems();
      expect(itemsFromDb.length, 1);
      expect(itemsFromDb.first.name, 'video_1.mp4');

      StorageService.downloadsNotifier.removeListener(listener);
    });

    test('removeItem removes correctly from storage', () async {
      final item1 = DownloadItemModel(
        id: 'id_1',
        name: 'a.mp4',
        type: 'video',
        sizeInBytes: 100,
        filePath: '/a.mp4',
        downloadedAt: DateTime.now(),
      );
      final item2 = DownloadItemModel(
        id: 'id_2',
        name: 'b.mp3',
        type: 'audio',
        sizeInBytes: 200,
        filePath: '/b.mp3',
        downloadedAt: DateTime.now(),
      );

      await StorageService.addItem(item1);
      await StorageService.addItem(item2);

      var items = await StorageService.getItems();
      expect(items.length, 2);

      await StorageService.removeItem('id_1');

      items = await StorageService.getItems();
      expect(items.length, 1);
      expect(items.first.id, 'id_2');
    });
  });
}
