import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/screens/browser_screen.dart';

void main() {
  group('Browser Back Navigation Tests', () {
    testWidgets('handleBackAction invokes onCloseTab when at root history', (
      tester,
    ) async {
      bool closedTab = false;
      final key = GlobalKey<InAppMediaBrowserScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppMediaBrowserScreen(
              key: key,
              webViewBuilder: _testWebViewBuilder,
              onCloseTab: () {
                closedTab = true;
              },
            ),
          ),
        ),
      );

      expect(key.currentState, isNotNull);

      // Trigger back action at root history
      final handled = await key.currentState!.handleBackAction();
      expect(handled, isTrue);
      expect(closedTab, isTrue);
    });

    testWidgets(
      'In-app AppBar back button triggers handleBackAction and onCloseTab',
      (tester) async {
        bool closedTab = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InAppMediaBrowserScreen(
                webViewBuilder: _testWebViewBuilder,
                onCloseTab: () {
                  closedTab = true;
                },
              ),
            ),
          ),
        );

        final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
        expect(backButton, findsOneWidget);

        await tester.tap(backButton);
        await tester.pumpAndSettle();

        expect(closedTab, isTrue);
      },
    );

    testWidgets(
      'Pushed route with Navigator.push pops when at root of browser',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute<void>(
                        builder: (_) => const InAppMediaBrowserScreen(
                          webViewBuilder: _testWebViewBuilder,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Browser'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Browser'));
        await tester.pumpAndSettle();

        expect(find.byType(InAppMediaBrowserScreen), findsOneWidget);

        // Tap in-app back arrow
        final backButton = find.byIcon(Icons.arrow_back_ios_new_rounded);
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // Browser should pop and return to previous route
        expect(find.byType(InAppMediaBrowserScreen), findsNothing);
        expect(find.text('Open Browser'), findsOneWidget);
      },
    );
  });
}

Widget _testWebViewBuilder(BuildContext context) => const SizedBox.shrink();
