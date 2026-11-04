import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/quick_download_dialog.dart';

void main() {
  testWidgets('overlay download dialog accepts a link when none was copied', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QuickDownloadDialog(videoTitle: '', allowUrlInput: true),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('quick_dialog_url_field')),
      findsOneWidget,
    );
    expect(
      find.text('Bağlantıyı düzenleyin veya video linki yapıştırın'),
      findsOneWidget,
    );
  });
}
