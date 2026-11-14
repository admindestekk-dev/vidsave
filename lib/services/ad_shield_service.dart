import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VidSave AdMob Fraud Prevention & Click Shield (Tıklama Sahtekarlığı Kalkanı)
///
/// Kural:
/// 1 saat içinde aynı cihazdan 3 kere reklama tıklanırsa, AdMob hesabının geçersiz trafik
/// cezası (Invalid Traffic) almasını önlemek ve kötü niyetli tıklama saldırılarını engellemek
/// için o cihaza tam 3 saat boyunca reklam gösterimi tamamen durdurulur (bypassed/gizlenir).
///
/// Parametreler:
/// - Pencere süresi: 1 saat (60 dakika)
/// - Maksimum tıklama eşiği: 3 tıklama
/// - Ceza/Soğuma süresi: 3 saat (180 dakika)
class AdShieldService {
  AdShieldService._();

  static final AdShieldService instance = AdShieldService._();

  static const String prefKeyClickTimestamps = 'vidsave_ad_click_timestamps';
  static const String prefKeyBlockedUntil = 'vidsave_ad_blocked_until';

  /// 1 saatlik inceleme penceresi
  static const Duration clickWindowDuration = Duration(hours: 1);

  /// 1 saat içindeki maksimum izin verilen tıklama sayısı
  static const int maxClicksAllowed = 3;

  /// Eşik aşıldığında uygulanacak ceza süresi (3 saat)
  static const Duration blockDuration = Duration(hours: 3);

  /// Reklamların şu an engelli olup olmadığını kontrol eder.
  /// Eğer 3 saatlik ceza süresi dolmuşsa engeli otomatik olarak kaldırır.
  Future<bool> isAdBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUntilMs = prefs.getInt(prefKeyBlockedUntil);

      if (blockedUntilMs != null) {
        final blockedUntil = DateTime.fromMillisecondsSinceEpoch(
          blockedUntilMs,
        );
        final now = DateTime.now();

        if (now.isBefore(blockedUntil)) {
          final remaining = blockedUntil.difference(now);
          debugPrint(
            'AdShieldService: Cihaz reklam engeli altında! Kalan süre: ${remaining.inMinutes} dakika.',
          );
          return true;
        } else {
          // Ceza süresi dolmuş, temizle
          await prefs.remove(prefKeyBlockedUntil);
          await prefs.remove(prefKeyClickTimestamps);
          debugPrint(
            'AdShieldService: 3 saatlik reklam engeli süresi doldu, engel kaldırıldı.',
          );
          return false;
        }
      }
    } catch (e) {
      debugPrint('AdShieldService isAdBlocked hatası: $e');
    }
    return false;
  }

  /// Reklama tıklandığında çağrılır.
  /// Tıklamayı kaydeder, son 1 saatteki tıklamaları sayar ve 3 veya daha fazla ise
  /// 3 saatlik engeli tetikler.
  ///
  /// Dönüş değeri: `true` ise cihaz yeni engellendi, `false` ise normal devam.
  Future<bool> registerAdClick() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Mevcut tıklama geçmişini oku
      final rawList = prefs.getString(prefKeyClickTimestamps);
      List<int> timestamps = [];
      if (rawList != null && rawList.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawList);
          if (decoded is List) {
            timestamps = decoded
                .map((e) => int.tryParse(e.toString()) ?? 0)
                .where((e) => e > 0)
                .toList();
          }
        } catch (_) {}
      }

      // Son 1 saat (clickWindowDuration) dışındakileri temizle
      final cutoff = now.subtract(clickWindowDuration).millisecondsSinceEpoch;
      timestamps = timestamps.where((ts) => ts > cutoff).toList();

      // Yeni tıklamayı ekle
      timestamps.add(now.millisecondsSinceEpoch);

      // Kaydet
      await prefs.setString(prefKeyClickTimestamps, jsonEncode(timestamps));

      debugPrint(
        'AdShieldService: Reklam tıklaması kaydedildi! Son 1 saatteki tıklama sayısı: ${timestamps.length} / $maxClicksAllowed',
      );

      // Eğer 1 saatte 3 veya daha fazla tıklama olduysa 3 saatlik engeli devreye al
      if (timestamps.length >= maxClicksAllowed) {
        final blockedUntil = now.add(blockDuration);
        await prefs.setInt(
          prefKeyBlockedUntil,
          blockedUntil.millisecondsSinceEpoch,
        );
        debugPrint(
          'AdShieldService [ALARM / KALKAN DEVREDE]: 1 saat içinde $maxClicksAllowed tıklama tespit edildi! '
          'Cihaza ${blockDuration.inHours} saat boyunca reklam gösterimi tamamen kapatıldı. '
          'Bitiş: $blockedUntil',
        );
        return true;
      }
    } catch (e) {
      debugPrint('AdShieldService registerAdClick hatası: $e');
    }
    return false;
  }

  /// Kalan engel süresini döner (Engelli değilse null)
  Future<Duration?> getRemainingBlockDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blockedUntilMs = prefs.getInt(prefKeyBlockedUntil);
      if (blockedUntilMs == null) return null;

      final blockedUntil = DateTime.fromMillisecondsSinceEpoch(blockedUntilMs);
      final now = DateTime.now();
      if (now.isBefore(blockedUntil)) {
        return blockedUntil.difference(now);
      }
    } catch (_) {}
    return null;
  }

  /// Testler ve manuel sıfırlama için
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefKeyBlockedUntil);
      await prefs.remove(prefKeyClickTimestamps);
    } catch (_) {}
  }
}
