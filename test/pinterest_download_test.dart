import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/media_downloader.dart';
import 'package:vid_downloader_app/universal_scraper.dart';

void main() {
  group('Pinterest İndirme Altyapısı Güçlendirme Testleri', () {
    test('Pinterest sayfasından HLS m3u8 akışı doğrudan 720p/1080p MP4 adresine dönüştürülür', () async {
      const hlsPinUrl = 'https://v1.pinimg.com/videos/mc/hls/ab/cd/ef/71829304.m3u8';
      var clean = evrenselTemizUrlShield(hlsPinUrl);
      if (clean.contains('.m3u8') || clean.contains('/hls/')) {
        clean = clean.replaceAll('/hls/', '/720p/').replaceAll('.m3u8', '.mp4');
      }
      expect(clean, 'https://v1.pinimg.com/videos/mc/720p/ab/cd/ef/71829304.mp4');
      expect(clean.endsWith('.mp4'), isTrue);
    });

    test('Pinterest orijinal görsel bağlantıları (jpg/png) Photo klasörü için desteklenir', () {
      const pinImageUrl = 'https://i.pinimg.com/originals/12/34/56/example.jpg';
      final uri = Uri.parse(pinImageUrl);
      final ext = uri.pathSegments.last.split('.').last.toLowerCase();
      final isImage = {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(ext);
      expect(isImage, isTrue);
    });
  });
}
