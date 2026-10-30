import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/downloads_screen.dart';
import 'package:vid_downloader_app/services/download_manager.dart';
import 'package:vid_downloader_app/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.clearAll();
  });

  testWidgets(
    'DownloadsScreen displays active download tasks with live controls',
    (WidgetTester tester) async {
      final task = DownloadManager.instance.startTask(
        id: 'active_1',
        title: 'Amazing Nature 4K Video',
        url: 'https://example.com/nature.mp4',
        type: 'video',
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      DownloadManager.instance.updateProgress(
        id: 'active_1',
        received: 5242880, // 5 MB
        total: 10485760, // 10 MB
        progress: 0.5,
        speed: '2.4 MB/s',
      );

      await tester.pumpWidget(const MaterialApp(home: DownloadsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('AKTİF İNDİRMELER'), findsOneWidget);
      expect(find.text('Amazing Nature 4K Video'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('5.0 MB / 10.0 MB'), findsOneWidget);
      expect(find.text('2.4 MB/s'), findsOneWidget);

      // Duraklat (Pause) butonuna bas
      expect(find.byTooltip('Duraklat'), findsOneWidget);
      await tester.tap(find.byTooltip('Duraklat'));
      await tester.pumpAndSettle();

      expect(task.isPaused, isTrue);
      expect(find.byTooltip('Devam Ettir'), findsOneWidget);

      // Devam ettir (Resume) butonuna bas
      await tester.tap(find.byTooltip('Devam Ettir'));
      await tester.pumpAndSettle();
      expect(task.isDownloading, isTrue);

      // Görevi tamamla
      DownloadManager.instance.completeTask('active_1');
      await tester.pumpAndSettle();
      expect(find.text('AKTİF İNDİRMELER'), findsNothing);
    },
  );
}
