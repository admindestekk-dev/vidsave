import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/download_format_sheet.dart';
import 'package:vid_downloader_app/media_downloader.dart';

void main() {
  group('DownloadFormatBottomSheet Tests', () {
    testWidgets('shows content info and format options, triggers callback on selection', (
      WidgetTester tester,
    ) async {
      DownloadKind? selectedKind;
      String? selectedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  DownloadFormatBottomSheet.show(
                    context: context,
                    url: 'https://www.instagram.com/reel/C8xyz123/',
                    initialTitle: 'Komik Kedi Videosu',
                    onFormatSelected: (kind, url) {
                      selectedKind = kind;
                      selectedUrl = url;
                    },
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      // Tap to open bottom sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // 1. Verify sheet title
      expect(find.text('İndirme formatı'), findsOneWidget);

      // 2. Verify content info card displays platform badge and title
      expect(find.text('Instagram • Reel / Post'), findsOneWidget);
      expect(find.text('Komik Kedi Videosu'), findsOneWidget);

      // 3. Verify format option buttons exist
      expect(find.byKey(const ValueKey('browser_download_video_option')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser_download_audio_option')), findsOneWidget);
      expect(find.text('Video (MP4)'), findsOneWidget);
      expect(find.text('Ses (MP3)'), findsOneWidget);

      // 4. Select Video (MP4)
      await tester.tap(find.byKey(const ValueKey('browser_download_video_option')));
      await tester.pumpAndSettle();

      expect(selectedKind, DownloadKind.video);
      expect(selectedUrl, 'https://www.instagram.com/reel/C8xyz123/');

      // Verify bottom sheet dismissed
      expect(find.text('İndirme formatı'), findsNothing);
    });
  });
}
