import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/screens/browser_screen.dart';

void main() {
  group('Browser Scheme Shield Tests (ERR_UNKNOWN_URL_SCHEME Protection)', () {
    test('Blocks external app schemes with NavigationActionPolicy.CANCEL', () {
      expect(
        shouldOverrideUrlLoading('fb://facewebmodal/f?href=https://m.facebook.com/watch'),
        equals(NavigationActionPolicy.CANCEL),
      );
      expect(
        shouldOverrideUrlLoading('fb://page/123456789'),
        equals(NavigationActionPolicy.CANCEL),
      );
      expect(
        shouldOverrideUrlLoading(
          'intent://facebook.com#Intent;scheme=fb;package=com.facebook.katana;end',
        ),
        equals(NavigationActionPolicy.CANCEL),
      );
      expect(
        shouldOverrideUrlLoading('whatsapp://send?text=https://example.com'),
        equals(NavigationActionPolicy.CANCEL),
      );
      expect(
        shouldOverrideUrlLoading('tg://resolve?domain=vidsave'),
        equals(NavigationActionPolicy.CANCEL),
      );
      expect(
        shouldOverrideUrlLoading('market://details?id=com.facebook.katana'),
        equals(NavigationActionPolicy.CANCEL),
      );
    });

    test('Allows standard http/https websites with NavigationActionPolicy.ALLOW', () {
      expect(
        shouldOverrideUrlLoading('https://www.facebook.com/reel/12345'),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        shouldOverrideUrlLoading('https://m.facebook.com/watch/?v=98765'),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        shouldOverrideUrlLoading('https://www.instagram.com/p/C1234/'),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        shouldOverrideUrlLoading('https://www.tiktok.com/@creator/video/123'),
        equals(NavigationActionPolicy.ALLOW),
      );
      expect(
        shouldOverrideUrlLoading('http://example.com/media/test.mp4'),
        equals(NavigationActionPolicy.ALLOW),
      );
    });

    testWidgets('InAppMediaBrowserScreen renders with scheme filter enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(
            initialUrl: 'https://m.facebook.com',
          ),
        ),
      );

      expect(find.byType(InAppMediaBrowserScreen), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
