import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/services/review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReviewService (Uygulama İçi Değerlendirme) Testleri', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ReviewService.instance.reset();
    });

    test('Başlangıçta has_requested_review değeri boştur', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ReviewService.prefKeyHasRequestedReview), isNull);
    });

    test('requestReviewIfNeeded çağrıldığında has_requested_review true olarak kaydedilir', () async {
      final prefs = await SharedPreferences.getInstance();

      await ReviewService.instance.requestReviewIfNeeded();

      expect(prefs.getBool(ReviewService.prefKeyHasRequestedReview), isTrue);
    });

    test('has_requested_review true ise bir daha asla tetiklenmez (tek seferlik ömür boyu kuralı)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ReviewService.prefKeyHasRequestedReview, true);

      // İkinci çağrıda tekrar çalıştırılmaya çalışıldığında değeri değiştirmemeli ve erken çıkmalı
      await ReviewService.instance.requestReviewIfNeeded();

      expect(prefs.getBool(ReviewService.prefKeyHasRequestedReview), isTrue);
    });
  });
}
