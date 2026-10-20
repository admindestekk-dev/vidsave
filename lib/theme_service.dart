import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulamanın Açık (Light) ve Koyu (Dark) tema durumunu yöneten ve
/// SharedPreferences ile kalıcı olarak saklayan reaktif servis.
class ThemeService {
  ThemeService._();

  static const String _themePrefKey = 'vidsave_dark_theme_enabled';

  /// Vurgu rengi: Turuncu-Mercan (#FFFF5436)
  static const Color primaryColor = Color(0xFFFF5436);

  /// Açık tema arka planı: Hafif Gri (#F8F9FA)
  static const Color lightBackgroundColor = Color(0xFFF8F9FA);

  /// Koyu tema arka planı: Premium Koyu Gri (#121212)
  static const Color darkBackgroundColor = Color(0xFF121212);

  /// Tema durumunu tüm ekranlarda anlık tetikleyen ValueNotifier
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Koyu temanın aktif olup olmadığını döndürür.
  static bool get isDarkMode => themeModeNotifier.value == ThemeMode.dark;

  /// Uygulama açılışında kayıtlı tema tercihini yükler.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool(_themePrefKey) ?? false;
      themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
      updateSystemUIOverlay(isDark);
    } catch (e) {
      debugPrint('ThemeService.initialize hatası: $e');
    }
  }

  /// Temayı açar veya kapatır ve SharedPreferences'a kaydeder.
  static Future<void> setDarkMode(bool isDark) async {
    themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    updateSystemUIOverlay(isDark);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themePrefKey, isDark);
    } catch (e) {
      debugPrint('ThemeService.setDarkMode hatası: $e');
    }
  }

  /// Durum çubuğu (Status Bar) ve gezinme çubuğu (Navigation Bar) simge renklerini
  /// temaya göre dinamik ayarlar:
  /// - Açık temada simgeler koyu (Brightness.dark), arka plan şeffaf/açık
  /// - Koyu temada simgeler açık/beyaz (Brightness.light), arka plan şeffaf/koyu
  static void updateSystemUIOverlay(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light, // iOS
        systemNavigationBarColor:
            isDark ? darkBackgroundColor : lightBackgroundColor,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  /// Açık Tema Tanımı
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        brightness: Brightness.light,
        surface: lightBackgroundColor,
      ),
      scaffoldBackgroundColor: lightBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackgroundColor,
        foregroundColor: Color(0xFF172B3A),
        centerTitle: false,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return Colors.grey.shade300;
        }),
      ),
    );
  }

  /// Koyu Tema Tanımı
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        brightness: Brightness.dark,
        surface: const Color(0xFF1E1E1E),
      ),
      scaffoldBackgroundColor: darkBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackgroundColor,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E1E1E),
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1E1E1E),
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF87949D),
      ),
      dividerColor: const Color(0xFF2A2A2A),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return Colors.grey.shade600;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return const Color(0xFF333333);
        }),
      ),
    );
  }
}
