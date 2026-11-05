import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/download_exception_handler.dart';
import 'package:vid_downloader_app/home_screen.dart';

void main() {
  group('FFmpeg ve Platform Sansür / Siber Kalkan Testleri', () {
    test('DownloadExceptionHandler FFmpeg rc: 1 ve rate limit hatalarını kurumsal metinle sansürler', () {
      const corporateMessage =
          'Yasal kısıtlamalar ve telif hakları politikaları gereği, ilgili platforma ait medyaların indirilmesi kısıtlanmıştır. VidSave; TikTok, Instagram ve Facebook platformlarında Pro bulut gücüyle 7/24 hizmet sunmaya devam etmektedir.';

      final ffmpegErr = Exception('FFmpeg MP3 dönüştürme başarısız oldu (rc: 1). failTrace output');
      final rateLimitErr = Exception('Rate Limit / IP Block detected from platform');
      final botErr = Exception('Platform bot algılama duvarı devrede');

      expect(DownloadExceptionHandler.getFriendlyMessage(ffmpegErr, null), corporateMessage);
      expect(DownloadExceptionHandler.getFriendlyMessage(rateLimitErr, null), corporateMessage);
      expect(DownloadExceptionHandler.getFriendlyMessage(botErr, null), corporateMessage);
    });

    testWidgets('QuickDownloadWindow hata aldığında ekrana teknik FFmpeg logu yerine kurumsal metin yansıtır', (
      tester,
    ) async {
      const corporateMessage =
          'Yasal kısıtlamalar ve telif hakları politikaları gereği, ilgili platforma ait medyaların indirilmesi kısıtlanmıştır. VidSave; TikTok, Instagram ve Facebook platformlarında Pro bulut gücüyle 7/24 hizmet sunmaya devam etmektedir.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuickDownloadWindow(initialUrl: 'https://vimeo.com/invalid_or_failing_video'),
          ),
        ),
      );

      expect(find.byType(QuickDownloadWindow), findsOneWidget);
      // Butona tıklayıp hata akışını tetikle
      final mp3Button = find.text('MP3 İndir');
      expect(mp3Button, findsOneWidget);
      await tester.tap(mp3Button);
      await tester.pumpAndSettle();

      // Ekranda veya SnackBar'da sansürlenmiş kurumsal metin aranır, teknik FFmpeg logu kesinlikle bulunmaz
      expect(find.text(corporateMessage), findsAtLeastNWidgets(1));
      expect(find.textContaining('rc: 1'), findsNothing);
      expect(find.textContaining('FFmpeg'), findsNothing);
    });
  });
}
