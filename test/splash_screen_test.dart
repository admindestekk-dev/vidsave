import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vid_downloader_app/main.dart';
import 'package:vid_downloader_app/splash_screen.dart';

void main() {
  testWidgets('splash shows the brand mark and a progress indicator', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    // The first frame renders before the fade/scale animation settles.
    expect(find.text('VidSave'), findsOneWidget);
    expect(find.text('PREMIUM VIDEO & MP3 DOWNLOADER'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the launch timer and the route transition elapse. pumpAndSettle would
    // spin forever here because the splash owns an indeterminate progress
    // indicator, so advance time explicitly instead.
    await tester.pump(SplashScreen.duration);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('splash hands over to the home page after its duration', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(VidSaveHomePage), findsNothing);

    await tester.pump(SplashScreen.duration);
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(VidSaveHomePage), findsOneWidget);
  });
}
