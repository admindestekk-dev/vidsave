import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/screens/browser_screen.dart';

void main() {
  group('Browser download button', () {
    test('allows all HTTP sites except YouTube', () {
      for (final url in [
        'https://www.facebook.com/reel/123',
        'https://instagram.com/reel/123',
        'https://www.tiktok.com/@user/video/123',
        'https://vimeo.com/123',
        'https://twitter.com/user/status/123',
        'https://x.com/user/status/123',
        'https://dailymotion.com/video/123',
        'https://pinterest.com/pin/123',
        'https://pin.it/abc123',
        'https://example.com/video',
        'https://youtube.com.evil.example/watch?v=123',
        'https://instagram.com.evil.example/reel/123',
      ]) {
        expect(isDownloadButtonAllowedUrl(url), isTrue, reason: url);
      }

      for (final url in [
        'https://youtube.com/watch?v=123',
        'https://music.youtube.com/watch?v=123',
        'https://youtu.be/abc123',
        'javascript:alert(1)',
      ]) {
        expect(isDownloadButtonAllowedUrl(url), isFalse, reason: url);
      }
    });

    testWidgets('hides the download button on YouTube', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://www.youtube.com/watch?v=abc123',
            showDownloadButton: true,
            webViewBuilder: _testWebViewBuilder,
          ),
        ),
      );

      final downloadButton = find.byKey(
        const ValueKey('browser_download_button'),
      );
      expect(downloadButton, findsNothing);
    });

    testWidgets('asks before closing and keeps button when cancelled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://www.instagram.com',
            showDownloadButton: true,
            webViewBuilder: _testWebViewBuilder,
          ),
        ),
      );

      final closeButton = find.byKey(
        const ValueKey('close_browser_download_button'),
      );
      final downloadButton = find.byKey(
        const ValueKey('browser_download_button'),
      );
      expect(downloadButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      expect(find.text('VidSave İndirme Butonu Kapatılıyor'), findsOneWidget);
      expect(downloadButton, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('cancel_close_download_button')),
      );
      await tester.pumpAndSettle();
      expect(downloadButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('confirm_close_download_button')),
      );
      await tester.pumpAndSettle();

      expect(downloadButton, findsNothing);
    });

    testWidgets('shows the button on any other website', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://www.google.com',
            showDownloadButton: true,
            webViewBuilder: _testWebViewBuilder,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('browser_download_button')),
        findsOneWidget,
      );
      expect(find.text('İNDİR'), findsOneWidget);
    });

    testWidgets('keeps the button active before media is detected', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://example.com/article',
            showDownloadButton: true,
            webViewBuilder: _testWebViewBuilder,
          ),
        ),
      );

      final downloadButton = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('browser_download_button')),
      );
      expect(downloadButton.onPressed, isNotNull);
    });

    testWidgets(
      'opens the MP4 and MP3 format selector without leaving browser',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: InAppMediaBrowserScreen(
              initialUrl: 'https://example.com/video',
              showDownloadButton: true,
              webViewBuilder: _testWebViewBuilder,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('browser_download_button')));
        await tester.pumpAndSettle();

        expect(find.text('İndirme formatı'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('browser_download_video_option')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('browser_download_audio_option')),
          findsOneWidget,
        );
        expect(find.byType(InAppMediaBrowserScreen), findsOneWidget);
      },
    );

    testWidgets('hides the download button by default when showDownloadButton is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://www.google.com',
            showDownloadButton: false,
            webViewBuilder: _testWebViewBuilder,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('browser_download_button')),
        findsNothing,
      );
    });
  });
}

Widget _testWebViewBuilder(BuildContext context) => const SizedBox.shrink();
