import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/auth_gate.dart';
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
  Future<BackendSettings> load() async =>
      const BackendSettings(baseUrl: 'https://api.example.test');

  @override
  Future<void> save(BackendSettings settings) async {}
}

Widget _buildGate(AuthService auth) => MaterialApp(
  home: AuthGate(
    authService: auth,
    authenticatedBuilder: (_) => const Text('home'),
    guestBuilder: (_) => const Text('welcome'),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch shows WelcomeScreen', (tester) async {
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
    );
    await tester.pumpWidget(_buildGate(auth));
    await tester.pumpAndSettle();

    expect(find.text('welcome'), findsOneWidget);
  });

  testWidgets('previous guest session goes directly to the app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      WelcomeScreen.prefKeyHasSeenWelcome: true,
    });
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
    );
    await tester.pumpWidget(_buildGate(auth));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
  });
}
