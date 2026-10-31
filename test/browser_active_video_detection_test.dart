import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/screens/browser_screen.dart';

void main() {
  group('Browser Active Video Detection Tests', () {
    testWidgets('Updates active video dynamically when user switches videos', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InAppMediaBrowserScreen(initialUrl: 'https://m.facebook.com'),
        ),
      );

      final state = tester.state(
        find.byType(InAppMediaBrowserScreen),
      ) as dynamic;

      // Initial state: no video active yet
      expect(state.detectedVideoUrl, isNull);
      expect(state.isVideoActive, isFalse);

      // 1. User starts watching Video 1 (e.g. first reel)
      final video1Payload = jsonEncode({
        'type': 'video_active',
        'mediaUrl': 'https://video.cdn.com/reel1.mp4',
        'pageUrl': 'https://www.instagram.com/reel/Reel1/',
        'title': 'Awesome Reel 1',
        'isPlaying': true,
      });

      state.handleIncomingDetectorMessage(video1Payload);
      await tester.pump();

      // State must now reflect Video 1
      expect(state.detectedVideoUrl, equals('https://video.cdn.com/reel1.mp4'));
      expect(state.isVideoActive, isTrue);
      expect(state.pageTitle, equals('Awesome Reel 1'));

      // 2. User scrolls to Video 2 and it starts playing
      final video2Payload = jsonEncode({
        'type': 'video_active',
        'mediaUrl': 'https://video.cdn.com/reel2.mp4',
        'pageUrl': 'https://www.instagram.com/reel/Reel2/',
        'title': 'Awesome Reel 2',
        'isPlaying': true,
      });

      state.handleIncomingDetectorMessage(video2Payload);
      await tester.pump();

      // State MUST switch to Video 2 (NOT stuck on Video 1!)
      expect(state.detectedVideoUrl, equals('https://video.cdn.com/reel2.mp4'));
      expect(state.isVideoActive, isTrue);
      expect(state.pageTitle, equals('Awesome Reel 2'));

      // 3. User scrolls to Video 3 (blob-based video, using post URL fallback)
      final video3Payload = jsonEncode({
        'type': 'video_active',
        'mediaUrl': 'blob:https://www.tiktok.com/12345',
        'pageUrl': 'https://www.tiktok.com/@user/video/7123456789',
        'title': 'Viral TikTok Video 3',
        'isPlaying': true,
      });

      state.handleIncomingDetectorMessage(video3Payload);
      await tester.pump();

      // State MUST switch to Video 3's post URL because media is blob
      expect(
        state.detectedVideoUrl,
        equals('https://www.tiktok.com/@user/video/7123456789'),
      );
      expect(state.isVideoActive, isTrue);
      expect(state.pageTitle, equals('Viral TikTok Video 3'));

      // 4. Raw direct URL fallback message
      state.handleIncomingDetectorMessage('https://cdn.example.com/video4.mp4');
      await tester.pump();

      expect(state.detectedVideoUrl, equals('https://cdn.example.com/video4.mp4'));
      expect(state.isVideoActive, isTrue);
    });
  });
}
