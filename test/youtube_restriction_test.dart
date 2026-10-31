import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/screens/home_screen.dart';

void main() {
  group('YouTube Legal Restriction Shield Tests', () {
    test('isYouTubeUrl detects all standard and short YouTube URLs', () {
      expect(
        isYouTubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isTrue,
      );
      expect(isYouTubeUrl('https://youtu.be/dQw4w9WgXcQ'), isTrue);
      expect(isYouTubeUrl('http://m.youtube.com/watch?v=123'), isTrue);
      expect(isYouTubeUrl('youtube.com/shorts/abc123xyz'), isTrue);
      expect(isYouTubeUrl('YOUTUBE.COM/watch?v=test'), isTrue);
      expect(isYouTubeUrl('https://youtu.be/abc?si=123'), isTrue);
    });

    test('isYouTubeUrl returns false for non-YouTube platforms', () {
      expect(isYouTubeUrl('https://www.instagram.com/reel/Cx12345/'), isFalse);
      expect(
        isYouTubeUrl('https://www.tiktok.com/@user/video/7123456789'),
        isFalse,
      );
      expect(
        isYouTubeUrl('https://www.facebook.com/watch?v=123456789'),
        isFalse,
      );
      expect(isYouTubeUrl('https://vimeo.com/123456'), isFalse);
      expect(isYouTubeUrl('https://twitter.com/i/status/123'), isFalse);
    });

    testWidgets(
      'YouTube URL entered into QuickDownloadWindow triggers dark premium legal dialog',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: QuickDownloadWindow(
                initialUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
              ),
            ),
          ),
        );

        // Tap the download/search button inside the QuickDownloadWindow
        final searchOrDownloadBtn = find.byKey(const Key('download_search_button'));
        expect(searchOrDownloadBtn, findsOneWidget);

        await tester.tap(searchOrDownloadBtn);
        await tester.pumpAndSettle();

        // Verify the AlertDialog is displayed
        expect(find.byType(AlertDialog), findsOneWidget);

        // Verify the legal gavel/scales icon is displayed
        expect(find.byIcon(Icons.gavel_rounded), findsOneWidget);

        // Verify the exact corporate Google Play compliance text
        expect(
          find.text(
            'Google Play Store Hizmet Şartları ve telif hakları politikaları gereği, '
            'YouTube platformuna ait videoların indirilmesi yasal olarak kısıtlanmıştır. '
            'VidSave; Instagram, TikTok ve Facebook platformlarında kesintisiz hizmet sunmaktadır.',
          ),
          findsOneWidget,
        );

        // Verify the orange 'ANLADIM' button is displayed
        final okButton = find.text('ANLADIM');
        expect(okButton, findsOneWidget);

        // Tap 'ANLADIM' to dismiss
        await tester.tap(okButton);
        await tester.pumpAndSettle();

        // Dialog should be dismissed
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'YouTube URL with Video İndir button also triggers the legal shield popup',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: QuickDownloadWindow(
                initialUrl: 'https://youtu.be/dQw4w9WgXcQ',
              ),
            ),
          ),
        );

        final videoBtn = find.text('Video İndir');
        expect(videoBtn, findsOneWidget);

        await tester.tap(videoBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('ANLADIM'), findsOneWidget);

        await tester.tap(find.text('ANLADIM'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Non-YouTube URL (Instagram) returns false from checkAndShowYouTubeRestriction',
      (tester) async {
        late bool wasRestricted;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      wasRestricted = checkAndShowYouTubeRestriction(
                        context,
                        'https://www.instagram.com/reel/C123456/',
                      );
                    },
                    child: const Text('Test'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Test'));
        await tester.pump();

        expect(wasRestricted, isFalse);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  });
}
