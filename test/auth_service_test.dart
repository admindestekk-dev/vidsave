import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';

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

void main() {
  const userId = '4bc45f62-2199-4fde-9695-899cc34766ca';

  test('register stores the server session and account identity', () async {
    final tokenStore = _MemoryTokenStore();
    final client = MockClient((request) async {
      expect(request.url.path, '/api/auth/register');
      expect(request.headers['X-Api-Key'], 'app-key');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['email'], 'person@example.com');
      expect(payload['password'], 'a secure password');
      return http.Response(
        jsonEncode({
          'status': 'ok',
          'token': 'opaque-session-token',
          'user': {'id': userId, 'email': 'person@example.com'},
        }),
        201,
      );
    });
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: tokenStore,
      httpClient: client,
    );

    final user = await auth.register(
      email: '  person@example.com ',
      password: 'a secure password',
    );

    expect(user.id, userId);
    expect(tokenStore.token, 'opaque-session-token');
    expect(await auth.userIdForRequests(), userId);
    expect(await auth.authorizationHeaders(), {
      'Authorization': 'Bearer opaque-session-token',
    });
  });

  test('login reports generic invalid-credentials feedback', () async {
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient(
        (_) async =>
            http.Response('{"error":{"code":"auth.invalid_credentials"}}', 401),
      ),
    );

    await expectLater(
      auth.login(email: 'wrong@example.com', password: 'wrong password'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'E-posta veya şifre hatalı.',
        ),
      ),
    );
  });

  test('expired session is cleared from secure token storage', () async {
    final tokenStore = _MemoryTokenStore()
      ..token = 'expired-token'
      ..userId = userId;
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: tokenStore,
      httpClient: MockClient(
        (_) async =>
            http.Response('{"error":{"code":"auth.session_invalid"}}', 401),
      ),
    );

    expect(await auth.currentUser(), isNull);
    expect(tokenStore.token, isNull);
    expect(tokenStore.userId, isNull);
  });
}
