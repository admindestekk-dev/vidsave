

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/lyrics_bottom_sheet.dart';

void main() {
  testWidgets('LyricsBottomSheet renders song title and empty state gracefully', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsBottomSheet(
            songTitle: 'Sagopa Kajmer - Ateşten Gömlek',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Şarkı Sözleri (Karaoke)'), findsOneWidget);
    expect(find.text('Sagopa Kajmer - Ateşten Gömlek'), findsOneWidget);
    expect(find.text('Bu parça için senkronize söz bulunamadı.'), findsOneWidget);
  });

  testWidgets('LyricsBottomSheet parses and displays lyrics lines', (tester) async {
    const rawLyrics = '[00:10.00]Gözlerimi kapatsam da nafile\n[00:15.50]Geceler hep aynı bilmece\nBu bir nakarat satırı';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsBottomSheet(
            songTitle: 'Test Song',
            lyrics: rawLyrics,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gözlerimi kapatsam da nafile'), findsOneWidget);
    expect(find.text('Geceler hep aynı bilmece'), findsOneWidget);
    expect(find.text('Bu bir nakarat satırı'), findsOneWidget);
  });
}
