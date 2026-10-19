import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/app_localizations.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/profile_screen.dart';
import 'package:vid_downloader_app/subscription_screen.dart';
import 'package:vid_downloader_app/welcome_screen.dart';

class _FakeSettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async => const BackendSettings(
    baseUrl: 'https://example.test',
    apiKey: 'test-key',
  );

  @override
  Future<void> save(BackendSettings settings) async {}
}

class _MemoryTokenStore implements AuthTokenStore {
  String? token = 'jwt-test-token-777';
  String? userId = 'user-uuid-888';

  @override
  Future<void> clearToken() async {
    token = null;
    userId = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> saveUserId(String value) async => userId = value;
}

Widget _buildProfileApp({required AuthService authService}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('tr'),
    home: ProfileScreen(authService: authService),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      SecureAuthTokenStore.prefKeyUserName: 'Test Kullanıcı',
      SecureAuthTokenStore.prefKeyUserEmail: 'testuser@example.com',
      SubscriptionScreen.prefKeyIsPremium: true,
      WelcomeScreen.prefKeyHasSeenWelcome: true,
    });
  });

  testWidgets(
    'ProfileScreen displays user info, red Delete Account button, and deletes account on confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool deleteEndpointCalled = false;
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/delete-account') {
          deleteEndpointCalled = true;
          return http.Response(jsonEncode({'status': 'ok', 'success': true}), 200);
        }
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'user': {
                'id': 'user-uuid-888',
                'email': 'testuser@example.com',
                'name': 'Test Kullanıcı',
                'avatarUrl': '',
              },
            }),
            200,
          );
        }
        return http.Response('{"error":"not_found"}', 404);
      });

      final tokenStore = _MemoryTokenStore();
      final authService = AuthService(
        settingsStore: _FakeSettingsStore(),
        tokenStore: tokenStore,
        httpClient: client,
      );

      await tester.pumpWidget(_buildProfileApp(authService: authService));
      await tester.pumpAndSettle();

      // Verify user info is loaded
      expect(find.text('Test Kullanıcı'), findsOneWidget);
      expect(find.text('testuser@example.com'), findsOneWidget);

      // Verify 'Hesabımı Sil' button exists
      final deleteButton = find.text('Hesabımı Sil');
      expect(deleteButton, findsOneWidget);

      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      // Confirmation dialog should be presented
      expect(find.text('Hesabı Kalıcı Olarak Sil'), findsOneWidget);
      final confirmBtn = find.text('Evet, Kalıcı Olarak Sil');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Deletion endpoint should have been triggered
      expect(deleteEndpointCalled, isTrue);

      // App should navigate to WelcomeScreen
      expect(find.byType(WelcomeScreen), findsOneWidget);

      // Stored token and preferences should be cleaned
      expect(await tokenStore.readToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SubscriptionScreen.prefKeyIsPremium), isNull);
    },
  );
}
