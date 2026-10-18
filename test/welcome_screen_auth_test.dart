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

  testWidgets('registration submits credentials and only then continues', (
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
        expect(request.url.path, '/api/auth/register');
        expect(request.headers['X-Api-Key'], 'app-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestEmail = body['email'] as String;
        expect(body['password'], 'correct horse battery staple');
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'token': 'server-issued-token',
            'user': {
              'id': '4bc45f62-2199-4fde-9695-899cc34766ca',
              'email': 'person@example.com',
            },
          }),
          201,
        );
      }),
    );

    await tester.pumpWidget(_buildApp(auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giriş Yap / Üye Ol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hesabınız yok mu? Hemen Üye Olun'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(
      find.byType(TextField).at(1),
      'correct horse battery staple',
    );
    await tester.tap(find.text('Kayıt Ol ve Başla'));
    await tester.pumpAndSettle();

    expect(requestEmail, 'person@example.com');
    expect(tokenStore.token, 'server-issued-token');
    expect(tokenStore.userId, '4bc45f62-2199-4fde-9695-899cc34766ca');
    expect(find.text('VidSave home'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome), isTrue);
  });

  testWidgets('invalid credentials keep the sign-in form open with feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient(
        (_) async =>
            http.Response('{"error":{"code":"auth.invalid_credentials"}}', 401),
      ),
    );
    await tester.pumpWidget(_buildApp(auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giriş Yap / Üye Ol'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong password');
    await tester.tap(find.text('Giriş Yap ve Başla'));
    await tester.pumpAndSettle();

    expect(find.text('E-posta veya şifre hatalı.'), findsOneWidget);
    expect(find.text('VidSave home'), findsNothing);
  });
}
