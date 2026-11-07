import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VidSave Ödüllü Reklam (Rewarded Ad) Tabanlı Pro Sunucu Kredi Yöneticisi.
///
/// Kullanıcı kısa bir test/ödüllü reklam videosu izlediğinde 3 indirme hakkı kazanır.
/// Bu haklar süresince Pro Sunucu hızı ve reklamsız indirme modu aktif olur.
class ProServerRewardService {
  ProServerRewardService._();
  static final ProServerRewardService instance = ProServerRewardService._();

  static const String prefKeyProCredits = 'vidsave_pro_credits';
  static const int rewardCreditsPerAd = 3;

  final ValueNotifier<int> proCreditsNotifier = ValueNotifier<int>(0);
  bool _isInitialized = false;

  /// Servisi başlatır ve mevcut kredi miktarını hafızadan okur.
  Future<void> init() async {
    if (_isInitialized) return;
    final credits = await getCredits();
    proCreditsNotifier.value = credits;
    _isInitialized = true;
  }

  /// Mevcut Pro indirme kredisi sayısını döndürür.
  Future<int> getCredits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final credits = prefs.getInt(prefKeyProCredits) ?? 0;
      proCreditsNotifier.value = credits;
      return credits;
    } catch (_) {
      return proCreditsNotifier.value;
    }
  }

  /// Reklam izleme ödülü olarak kredi ekler (varsayılan +3).
  Future<int> addCredits([int amount = rewardCreditsPerAd]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(prefKeyProCredits) ?? 0;
      final updated = current + amount;
      await prefs.setInt(prefKeyProCredits, updated);
      proCreditsNotifier.value = updated;
      debugPrint('ProServerRewardService: $amount Pro hak eklendi. Toplam: $updated');
      return updated;
    } catch (e) {
      proCreditsNotifier.value += amount;
      return proCreditsNotifier.value;
    }
  }

  /// Bir indirme tamamlandığında 1 kredi düşer.
  /// Kredi varsa `true`, kredi 0 ise `false` döner.
  Future<bool> consumeCredit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(prefKeyProCredits) ?? 0;
      if (current > 0) {
        final updated = current - 1;
        await prefs.setInt(prefKeyProCredits, updated);
        proCreditsNotifier.value = updated;
        debugPrint('ProServerRewardService: 1 Pro hak kullanıldı. Kalan: $updated');
        return true;
      }
      return false;
    } catch (_) {
      if (proCreditsNotifier.value > 0) {
        proCreditsNotifier.value -= 1;
        return true;
      }
      return false;
    }
  }

  /// Pro sunucu modunun aktif olup olmadığını kontrol eder.
  Future<bool> isProServerActive() async {
    final credits = await getCredits();
    return credits > 0;
  }

  /// Test veya sıfırlama amaçlı kredileri sıfırlar.
  Future<void> clearCredits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefKeyProCredits);
      proCreditsNotifier.value = 0;
    } catch (_) {
      proCreditsNotifier.value = 0;
    }
  }
}
