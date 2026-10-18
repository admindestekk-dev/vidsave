import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeService.setDarkMode(false);
  });

  group('ThemeService Dark / Light Mode', () {
    test(
      'default theme is light with correct background and primary colors',
      () {
        expect(ThemeService.themeModeNotifier.value, ThemeMode.light);
        expect(ThemeService.isDarkMode, isFalse);

        final lightTheme = ThemeService.lightTheme;
        expect(lightTheme.brightness, Brightness.light);
        expect(lightTheme.primaryColor, const Color(0xFFFF5436));
        expect(lightTheme.scaffoldBackgroundColor, const Color(0xFFF8F9FA));
      },
    );

    test('dark theme has correct background and primary colors', () {
      final darkTheme = ThemeService.darkTheme;
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.primaryColor, const Color(0xFFFF5436));
      expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF121212));
    });

    test('toggling dark mode updates themeModeNotifier and persists to SharedPreferences', () async {
      bool notified = false;
      void listener() {
        notified = true;
      }

      ThemeService.themeModeNotifier.addListener(listener);

      // Turn ON dark mode
      await ThemeService.setDarkMode(true);
      expect(notified, isTrue);
      expect(ThemeService.themeModeNotifier.value, ThemeMode.dark);
      expect(ThemeService.isDarkMode, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('vidsave_dark_theme_enabled'), isTrue);

      // Turn OFF dark mode
      await ThemeService.setDarkMode(false);
      expect(ThemeService.themeModeNotifier.value, ThemeMode.light);
      expect(ThemeService.isDarkMode, isFalse);
      expect(prefs.getBool('vidsave_dark_theme_enabled'), isFalse);

      ThemeService.themeModeNotifier.removeListener(listener);
    });
  });
}
