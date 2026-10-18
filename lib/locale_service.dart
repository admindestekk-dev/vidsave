import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VidSave uygulamasının aktif dilini (Locale) yöneten ve
/// SharedPreferences ile kalıcı olarak saklayan reaktif servis.
class LocaleService {
  LocaleService._();

  static const String _localePrefKey = 'vidsave_selected_locale';

  /// Dil durumunu tüm ekranlarda anlık tetikleyen ValueNotifier
  static final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(
    null,
  );

  /// Geçerli dil kodu (varsayılan 'tr')
  static String get currentLanguageCode =>
      localeNotifier.value?.languageCode.toLowerCase() ?? 'tr';

  /// Uygulama açılışında kayıtlı dil tercihini yükler.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_localePrefKey);
      if (savedCode != null && savedCode.isNotEmpty) {
        localeNotifier.value = Locale(savedCode);
      }
    } catch (e) {
      debugPrint('LocaleService.initialize hatası: $e');
    }
  }

  /// Dili değiştirir, ValueNotifier'ı günceller ve SharedPreferences'a kaydeder.
  static Future<void> setLocale(Locale locale) async {
    localeNotifier.value = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localePrefKey, locale.languageCode.toLowerCase());
    } catch (e) {
      debugPrint('LocaleService.setLocale hatası: $e');
    }
  }
}

/// Kolay erişim için BuildContext extension'ı
extension LocalizationContextExtension on BuildContext {
  Future<void> setLocale(Locale locale) => LocaleService.setLocale(locale);
}
