import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/auth_gate.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/screens/onboarding_screen.dart';

class _MockTokenStore implements AuthTokenStore {
  @override
  Future<void> clearToken() async {}
  @override
  Future<String?> readToken() async => null;
  @override
  Future<String?> readUserId() async => null;
  @override
  Future<void> saveToken(String value) async {}
  @override
  Future<void> saveUserId(String value) async {}
}

class _MockSettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async =>
      const BackendSettings(baseUrl: 'https://api.example.test');
  @override
  Future<void> save(BackendSettings settings) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OnboardingScreen & SharedPreferences Flow', () {
    testWidgets('renders all 3 steps with PageView, Dots and Next/Finish buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            homeBuilder: (_) => const Scaffold(body: Text('Home Page')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Adım kontrolü
      expect(find.text('ADIM 1'), findsOneWidget);
      expect(find.text('Linki Kopyala'), findsOneWidget);
      expect(find.text('İLERİ'), findsOneWidget);
      expect(find.text('GEÇ'), findsOneWidget);

      // 2. Adıma ilerle
      await tester.tap(find.byKey(const Key('onboarding_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('ADIM 2'), findsOneWidget);
      expect(find.text('VidSave\'e Yapıştır'), findsOneWidget);
      expect(find.text('İLERİ'), findsOneWidget);

      // 3. Adıma ilerle
      await tester.tap(find.byKey(const Key('onboarding_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('ADIM 3'), findsOneWidget);
      expect(find.text('Formatı Seç ve İndir'), findsOneWidget);
      expect(find.text('BAŞLA'), findsOneWidget);

      // BAŞLA butonuna tıklandığında SharedPreferences kaydedilir ve ana sayfaya geçilir
      await tester.tap(find.byKey(const Key('onboarding_action_button')));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);

      final isFirstTime = await OnboardingScreen.checkIsFirstTime();
      expect(isFirstTime, isFalse);
    });

    testWidgets('tapping GEÇ (Skip) completes onboarding immediately', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            homeBuilder: (_) => const Scaffold(body: Text('Home Page')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GEÇ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      await tester.pumpAndSettle();

      expect(find.text('Home Page'), findsOneWidget);

      final isFirstTime = await OnboardingScreen.checkIsFirstTime();
      expect(isFirstTime, isFalse);
    });

    testWidgets('AuthGate displays OnboardingScreen when isFirstTime is true', (
      WidgetTester tester,
    ) async {
      final auth = AuthService(
        settingsStore: _MockSettingsStore(),
        tokenStore: _MockTokenStore(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authService: auth,
            isFirstTime: true,
            authenticatedBuilder: (_) => const Scaffold(body: Text('Authenticated Home')),
            guestBuilder: (_) => const Scaffold(body: Text('Welcome Guest')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Linki Kopyala'), findsOneWidget);
    });
  });
}
