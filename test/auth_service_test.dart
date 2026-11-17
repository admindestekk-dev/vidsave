import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vid_downloader_app/auth_service.dart';
import 'package:vid_downloader_app/backend_settings.dart';
import 'package:vid_downloader_app/subscription_screen.dart';

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

class _FailingGoogleSignIn extends Fake implements GoogleSignIn {
  _FailingGoogleSignIn(this.error, {this.failDuringInitialization = false});

  final GoogleSignInException error;
  final bool failDuringInitialization;
  String? serverClientId;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    this.serverClientId = serverClientId;
    if (failDuringInitialization) throw error;
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) async => throw error;
}

class _GoogleAccount extends Fake implements GoogleSignInAccount {
  @override
  GoogleSignInAuthentication get authentication =>
      const GoogleSignInAuthentication(idToken: 'google-id-token');
}

class _SuccessfulGoogleSignIn extends Fake implements GoogleSignIn {
  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {}

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const <String>[],
  }) async => _GoogleAccount();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = '4bc45f62-2199-4fde-9695-899cc34766ca';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('native Google token is exchanged for Firebase token sent to backend', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: _MemoryTokenStore(),
      firebaseTokenExchange: (token) async {
        expect(token, 'google-id-token');
        return 'firebase-id-token';
      },
      httpClient: MockClient((request) async {
        expect(jsonDecode(request.body), {'idToken': 'firebase-id-token'});
        return http.Response(jsonEncode({
          'token': 'session-token',
          'user': {'id': userId, 'email': 'person@example.com'},
        }), 200);
      }),
    );

    final user = await auth.loginWithGoogle(
      googleSignInClient: _SuccessfulGoogleSignIn(),
    );
    expect(user.email, 'person@example.com');
  });

  test('empty Firebase token is rejected before contacting backend', () async {
    final auth = AuthService(
      httpClient: MockClient((_) async => fail('Unexpected backend request')),
    );
    await expectLater(
      auth.loginWithGoogle(idToken: ''),
      throwsA(isA<AuthException>().having(
        (error) => error.code,
        'code',
        'auth.token_missing',
      )),
    );
  });

  test('Firebase exchange failure does not contact the backend', () async {
    final auth = AuthService(
      firebaseTokenExchange: (_) async => throw StateError('Firebase unavailable'),
      httpClient: MockClient((_) async => fail('Unexpected backend request')),
    );
    await expectLater(
      auth.loginWithGoogle(googleSignInClient: _SuccessfulGoogleSignIn()),
      throwsA(isA<AuthException>().having(
        (error) => error.message,
        'message',
        contains('Firebase unavailable'),
      )),
    );
  });

  test('Google sign-in preserves Android API error and uses generated configuration', () async {
    final google = _FailingGoogleSignIn(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'SDK reported an exception: 10: DEVELOPER_ERROR',
      ),
    );
    final auth = AuthService();

    await expectLater(
      auth.loginWithGoogle(googleSignInClient: google),
      throwsA(isA<AuthException>().having(
        (error) => error.message,
        'message',
        contains('10: DEVELOPER_ERROR'),
      )),
    );
    expect(google.serverClientId, isNull);
  });

  test('Google initialization errors retain their details', () async {
    final google = _FailingGoogleSignIn(
      const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'Invalid server client ID',
      ),
      failDuringInitialization: true,
    );

    await expectLater(
      AuthService().loginWithGoogle(googleSignInClient: google),
      throwsA(isA<AuthException>().having(
        (error) => error.message,
        'message',
        contains('Invalid server client ID'),
      )),
    );
  });

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

    await SubscriptionScreen.savePremiumStatus(DateTime.utc(2099));
    expect(await auth.currentUser(), isNull);
    expect(tokenStore.token, isNull);
    expect(tokenStore.userId, isNull);
    expect(await SubscriptionScreen.readPremiumStatus(), isFalse);
  });

  test('logging out clears the local premium entitlement', () async {
    final tokenStore = _MemoryTokenStore()..token = 'session-token';
    final auth = AuthService(
      settingsStore: _SettingsStore(),
      tokenStore: tokenStore,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    await SubscriptionScreen.savePremiumStatus(DateTime.utc(2099));

    await auth.logout();

    expect(await SubscriptionScreen.readPremiumStatus(), isFalse);
    expect(tokenStore.token, isNull);
  });
}
