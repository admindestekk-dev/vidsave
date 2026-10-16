import 'package:flutter_test/flutter_test.dart';
import 'package:vid_downloader_app/download_platforms.dart';

void main() {
  group('DownloadPlatform URL domain matching', () {
    final fb = kDownloadPlatforms.firstWhere((p) => p.label.contains('FB'));
    final ig = kDownloadPlatforms.firstWhere((p) => p.label.contains('İG'));
    final tt = kDownloadPlatforms.firstWhere((p) => p.label.contains('TT'));
    final vm = kDownloadPlatforms.firstWhere((p) => p.label.contains('VM'));
    final x = kDownloadPlatforms.firstWhere((p) => p.label.contains('X'));
    final dm = kDownloadPlatforms.firstWhere((p) => p.label.contains('DM'));
    final mp3 = kDownloadPlatforms.firstWhere((p) => p.isAudio);

    test('Facebook only matches Facebook URLs', () {
      expect(fb.matchesUrl('https://www.facebook.com/watch/?v=123'), isTrue);
      expect(fb.matchesUrl('https://fb.watch/xyz'), isTrue);
      expect(fb.matchesUrl('https://www.instagram.com/reel/abc'), isFalse);
      expect(fb.matchesUrl('https://tiktok.com/@user/video/1'), isFalse);
    });

    test('Instagram only matches Instagram URLs', () {
      expect(ig.matchesUrl('https://www.instagram.com/reel/abc123/'), isTrue);
      expect(ig.matchesUrl('https://instagr.am/p/xyz'), isTrue);
      expect(ig.matchesUrl('https://www.facebook.com/watch/?v=123'), isFalse);
      expect(ig.matchesUrl('https://twitter.com/status/1'), isFalse);
    });

    test('TikTok only matches TikTok URLs', () {
      expect(tt.matchesUrl('https://www.tiktok.com/@user/video/12345'), isTrue);
      expect(tt.matchesUrl('https://vm.tiktok.com/ZM8x/'), isTrue);
      expect(tt.matchesUrl('https://instagram.com/reel/abc'), isFalse);
    });

    test('Vimeo only matches Vimeo URLs', () {
      expect(vm.matchesUrl('https://vimeo.com/123456789'), isTrue);
      expect(vm.matchesUrl('https://facebook.com/watch'), isFalse);
    });

    test('X / Twitter matches x.com and twitter.com URLs', () {
      expect(x.matchesUrl('https://x.com/user/status/123'), isTrue);
      expect(x.matchesUrl('https://twitter.com/user/status/123'), isTrue);
      expect(x.matchesUrl('https://instagram.com/p/123'), isFalse);
    });

    test('Dailymotion matches dailymotion.com and dai.ly URLs', () {
      expect(dm.matchesUrl('https://www.dailymotion.com/video/xanjbk6'), isTrue);
      expect(dm.matchesUrl('https://dai.ly/xanjbk6'), isTrue);
      expect(dm.matchesUrl('https://youtube.com/watch?v=123'), isFalse);
    });

    test('MP3 platform allows all URLs and music queries', () {
      expect(mp3.matchesUrl('https://youtube.com/watch?v=123'), isTrue);
      expect(mp3.matchesUrl('https://instagram.com/reel/123'), isTrue);
      expect(mp3.matchesUrl('https://soundcloud.com/track'), isTrue);
      expect(mp3.matchesUrl('Sagopa Kajmer Ateşten Gömlek'), isTrue);
    });
  });
}
