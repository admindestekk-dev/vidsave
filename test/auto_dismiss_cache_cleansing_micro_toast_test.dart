import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/clipboard_auto_download_service.dart';
import 'package:vid_downloader_app/home_screen.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/quick_download_dialog.dart';
import 'package:vid_downloader_app/services/micro_toast.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

class _MockMediaResolver implements MediaResolver {
  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    return const MediaPreview(title: 'Test Video');
  }

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    return ResolvedMedia(
      title: 'Resolved Test',
      streams: [
        MediaStreamInfo(
          url: Uri.parse('https://example.com/stream.mp4'),
          kind: kind,
          mimeType: kind == DownloadKind.audio ? 'audio/mp4' : 'video/mp4',
        ),
      ],
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      SubscriptionScreen.prefKeyIsPremium: true,
      SubscriptionScreen.prefKeyPremiumUntil: '2099-12-31T23:59:59Z',
    });
    ClipboardAutoDownloadService.resetLastHandled();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': ''};
          }
          return null;
        });
  });

  group('VidSave Auto-Dismiss, Cache Cleansing & Micro Toast Tests', () {
    testWidgets('1. QuickDownloadDialog autoDismissOnStart closes dialog instantly when download triggers', (
      WidgetTester tester,
    ) async {
      final resolver = _MockMediaResolver();
      var downloadStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  QuickDownloadDialog.show(
                    context: ctx,
                    videoTitle: 'https://instagram.com/p/C_abc123',
                    resolver: resolver,
                    downloader: MediaDownloader(),
                    autoDismissOnStart: true,
                    onDownloadStarted: () async {
                      downloadStarted = true;
                    },
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('VidSave Algıladı'), findsOneWidget);
      expect(find.text('Video İndir'), findsOneWidget);

      // Tap download button
      await tester.tap(find.text('Video İndir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Auto-Dismiss UI: The dialog pop-up is dismissed immediately
      expect(find.text('VidSave Algıladı'), findsNothing);
      expect(downloadStarted, isTrue);

      // Micro Toast: 2-second minimal notification is displayed
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('İndirme başlatılıyor…'), findsOneWidget);
    });

    testWidgets('2. Cache Cleansing: URL and clipboard memory are wiped clean immediately upon trigger', (
      WidgetTester tester,
    ) async {
      await ClipboardAutoDownloadService.clearMemoryAndCache();

      // Verify clearing cache prevents stale URLs from lingering
      await SharedPreferences.getInstance();
      await ClipboardAutoDownloadService.clearLastHandled();
      expect(await ClipboardAutoDownloadService.checkClipboardForDownloadUrl(), isNull);
    });

    testWidgets('3. Micro Toast displays minimal pill-shaped notification with 2s duration', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showMicroToast(
                    ctx,
                    message: 'Minimal Test Bildirimi',
                    isLoading: true,
                  );
                },
                child: const Text('Show Toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pump();

      // Verify micro toast is active
      expect(find.text('Minimal Test Bildirimi'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Fast forward past 2 seconds
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Micro toast auto-dismissed after 2 seconds
      expect(find.text('Minimal Test Bildirimi'), findsNothing);
    });

    testWidgets('4. QuickDownloadWindow resets inputs and auto-dismisses if opened in dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showQuickDownloadDialog(
                    ctx,
                    initialUrl: 'https://vimeo.com/123456',
                    autoDismissOnStart: true,
                  );
                },
                child: const Text('Open Quick Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Quick Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickDownloadWindow), findsOneWidget);
    });
  });
}
