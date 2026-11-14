import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/services/ad_shield_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdShieldService (Reklam Tıklama Kalkanı) Testleri', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AdShieldService.instance.reset();
    });

    test('Başlangıçta reklam engeli aktif değildir', () async {
      final isBlocked = await AdShieldService.instance.isAdBlocked();
      expect(isBlocked, isFalse);
    });

    test('1 saat içinde 1 veya 2 tıklama yapıldığında engel tetiklenmez', () async {
      final shield = AdShieldService.instance;

      final blocked1 = await shield.registerAdClick();
      expect(blocked1, isFalse);
      expect(await shield.isAdBlocked(), isFalse);

      final blocked2 = await shield.registerAdClick();
      expect(blocked2, isFalse);
      expect(await shield.isAdBlocked(), isFalse);
    });

    test('1 saat içinde 3 tıklama yapıldığında 3 saatlik engel anında devreye girer', () async {
      final shield = AdShieldService.instance;

      await shield.registerAdClick(); // 1. tıklama
      await shield.registerAdClick(); // 2. tıklama
      final blocked3 = await shield.registerAdClick(); // 3. tıklama

      expect(blocked3, isTrue, reason: '3. tıklamada engel devreye girmeli');
      expect(await shield.isAdBlocked(), isTrue);

      final remaining = await shield.getRemainingBlockDuration();
      expect(remaining, isNotNull);
      expect(remaining!.inMinutes, greaterThan(170));
      expect(remaining.inMinutes, lessThanOrEqualTo(180));
    });

    test('1 saatten eski tıklamalar pencere dışına çıkar ve sayılmaz', () async {
      final shield = AdShieldService.instance;
      final prefs = await SharedPreferences.getInstance();

      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
      // 2 saat önce 2 tıklama olmuştu
      await prefs.setString(
        AdShieldService.prefKeyClickTimestamps,
        jsonEncode([twoHoursAgo, twoHoursAgo + 1000]),
      );

      // Şimdi yeni 1 tıklama yapıldı
      final blocked = await shield.registerAdClick();
      expect(blocked, isFalse, reason: 'Eski tıklamalar temizlendiği için toplam 1 tıklama olmalı');
      expect(await shield.isAdBlocked(), isFalse);
    });

    test('3 saatlik engel süresi dolduğunda engel otomatik kalkar', () async {
      final shield = AdShieldService.instance;
      final prefs = await SharedPreferences.getInstance();

      // Engeli geçmiş bir zamana ayarla (4 saat önce engel bitmişti)
      final fourHoursAgo = DateTime.now().subtract(const Duration(hours: 4)).millisecondsSinceEpoch;
      await prefs.setInt(AdShieldService.prefKeyBlockedUntil, fourHoursAgo);

      final isBlocked = await shield.isAdBlocked();
      expect(isBlocked, isFalse, reason: '3 saat dolduğu için engel kaldırılmış olmalı');
      expect(prefs.getInt(AdShieldService.prefKeyBlockedUntil), isNull);
    });
  });
}
