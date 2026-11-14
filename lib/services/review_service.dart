import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VidSave Kullanıcı Değerlendirme Servisi (In-App Review)
///
/// Kullanıcı uygulamadan çıkmadan Google Play Store içi değerlendirme dialogunu açar.
/// Ömür boyu yalnızca 1 kez gösterilir (has_requested_review == true ise bir daha asla tetiklenmez).
class ReviewService {
  ReviewService._();

  static final ReviewService instance = ReviewService._();

  static const String prefKeyHasRequestedReview = 'has_requested_review';

  final InAppReview _inAppReview = InAppReview.instance;

  /// İlk indirme başarıyla tamamlandıktan 2 saniye sonra tetiklenir.
  /// Kullanıcı daha önce değerlendirme popup'ını görmüşse hiçbir şey yapmaz.
  Future<void> requestReviewIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRequested = prefs.getBool(prefKeyHasRequestedReview) ?? false;

      if (hasRequested) {
        debugPrint(
          'ReviewService: Değerlendirme isteği daha önce yapılmış, atlanıyor.',
        );
        return;
      }

      // 2 saniyelik gecikme (kullanıcının indirme bitti hissini yaşaması için)
      await Future<void>.delayed(const Duration(seconds: 2));

      // Kontrolü tekrar yap (olası eşzamanlı indirmelerde çifte tetiklemeyi önlemek için)
      final stillNotRequested =
          !(prefs.getBool(prefKeyHasRequestedReview) ?? false);
      if (!stillNotRequested) return;

      // Uygulama içi inceleme özelliği cihazda ve platformda destekleniyor mu?
      final isAvailable = await _inAppReview.isAvailable();
      debugPrint(
        'ReviewService: In-App Review kullanılabilir mi: $isAvailable',
      );

      if (isAvailable) {
        // Çağrı yapıldığı an veya hemen öncesinde has_requested_review değerini true olarak kaydet
        await prefs.setBool(prefKeyHasRequestedReview, true);
        debugPrint(
          'ReviewService: InAppReview.requestReview() tetikleniyor...',
        );
        await _inAppReview.requestReview();
      } else {
        // Cihazda Play Store kurulu değilse veya desteklenmiyorsa da true işaretle ki sürekli denemesin
        await prefs.setBool(prefKeyHasRequestedReview, true);
        debugPrint(
          'ReviewService: In-App Review bu cihazda desteklenmiyor, bayrak kaydedildi.',
        );
      }
    } catch (e, st) {
      debugPrint('ReviewService requestReviewIfNeeded hatası: $e\n$st');
    }
  }

  /// Testler veya hata ayıklama için sıfırlama metodu
  @visibleForTesting
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefKeyHasRequestedReview);
    } catch (_) {}
  }
}
