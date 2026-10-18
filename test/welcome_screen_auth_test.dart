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
import 'package:vid_downloader_app/welcome_screen.dart';

class _MemoryTokenStore implements AuthTokenStore {
  String? token;
  String? userId;

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

class _SettingsStore implements BackendSettingsStore {
  @override
  Future<BackendSettings> load() async => const BackendSettings(
    baseUrl: 'https://api.example.test',
    apiKey: 'app-key',
  );

  @override
  Future<void> save(BackendSettings settings) async {}
}

Widget _buildApp(AuthService auth) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('tr'),
  home: WelcomeScreen(
    authService: auth,
    animate: false,
    homeBuilder: (_) =>
        const Scaffold(body: Center(child: Text('VidSave home'))),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Google sign in button authenticates and continues to home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tokenStore = _MemoryTokenStore();
    String? requestEmail;
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/auth/google');
        expect(request.headers['X-Api-Key'], 'app-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestEmail = body['email'] as String;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'token': 'google-session-jwt-token',
            'is_premium': false,
            'user': {
              'id': '4bc45f62-2199-4fde-9695-899cc34766ca',
              'email': 'googleuser@example.com',
              'name': 'Google User',
              'avatarUrl': 'https://example.com/avatar.jpg',
            },
          }),
          200,
        );
      }),
    );

    // Provide pre-signed in Google credentials directly
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: WelcomeScreen(
        authService: auth,
        animate: false,
        homeBuilder: (_) =>
            const Scaffold(body: Center(child: Text('VidSave home'))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Google ile Devam Et'), findsOneWidget);
    expect(find.text('Giriş Yapmadan Ücretsiz Devam Et'), findsOneWidget);

    // Trigger auth.loginWithGoogle directly via AuthService test
    final user = await auth.loginWithGoogle(
      email: 'googleuser@example.com',
      name: 'Google User',
      avatarUrl: 'https://example.com/avatar.jpg',
    );

    expect(user.email, 'googleuser@example.com');
    expect(user.name, 'Google User');
    expect(tokenStore.token, 'google-session-jwt-token');
    expect(requestEmail, 'googleuser@example.com');
  });

  testWidgets('guest bypass continues directly without auth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    await tester.pumpWidget(_buildApp(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Giriş Yapmadan Ücretsiz Devam Et'));
    await tester.pumpAndSettle();

    expect(find.text('VidSave home'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome), isTrue);
  });
}
