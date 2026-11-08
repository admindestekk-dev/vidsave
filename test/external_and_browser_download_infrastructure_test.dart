import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/clipboard_auto_download_service.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

void main() {
  group('Dış Uygulama ve Tarayıcı İndirme Altyapısı Testleri', () {
    test('1. Dış uygulamalardan paylaşılan metinli linkleri başarıyla ayıklar ve temizler', () {
      const sharedInstagram =
          'Harika bir video buldum hemen izle: https://www.instagram.com/reel/C999999/?igsh=abcdef123';
      final extracted = ClipboardAutoDownloadService.extractUrl(
        sharedInstagram,
      );
      expect(extracted, isNotNull);
      expect(extracted, contains('instagram.com/reel/C999999/'));

      final cleaned = evrenselTemizUrl(sharedInstagram);
      expect(
        cleaned.startsWith('https://www.instagram.com/reel/C999999/'),
        isTrue,
      );
      expect(cleaned.contains('Harika'), isFalse);
    });

    test('2. TikTok ve Twitter/X paylaşım metinlerinden linki kusursuz süzer', () {
      const sharedTikTok =
          'Kullanıcının videosuna göz at! #trend https://vt.tiktok.com/ZS1234567/';
      final cleaned = evrenselTemizUrl(sharedTikTok);
      expect(cleaned.startsWith('https://vt.tiktok.com/ZS1234567/'), isTrue);
      expect(cleaned.contains('#trend'), isFalse);

      const sharedTwitter =
          'Günün haberi: https://x.com/user/status/987654321?s=20';
      final cleanedTwitter = evrenselTemizUrlShield(sharedTwitter);
      expect(
        cleanedTwitter.startsWith('https://x.com/user/status/987654321'),
        isTrue,
      );
      expect(cleanedTwitter.contains('Günün'), isFalse);
    });

    test('3. Protokolsüz //cdn.com ile başlayan akış bağlantılarını HTTPS ile güvenle tamamlar', () {
      const schemelessUrl = '//v16-default.tiktokcdn.com/video/media.mp4';
      final cleaned = evrenselTemizUrl(schemelessUrl);
      expect(
        cleaned.startsWith('https://v16-default.tiktokcdn.com/video/media.mp4'),
        isTrue,
      );
    });
  });
}
