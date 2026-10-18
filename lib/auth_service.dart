import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'backend_settings.dart';
import 'user_identity_service.dart';

class AuthUser {
  const AuthUser({required this.id, required this.email});

  final String id;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(id: json['id'] as String, email: json['email'] as String);
  }
}

class AuthException implements Exception {
  const AuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthTokenStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<String?> readUserId();
  Future<void> saveUserId(String userId);
  Future<void> clearToken();
}

class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'vidsave.auth.session_token';
  static const _userIdKey = 'vidsave.auth.user_id';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  @override
  Future<void> saveUserId(String userId) =>
      _storage.write(key: _userIdKey, value: userId);

  @override
  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
  }
}

/// Email/password API client. Session tokens are persisted only in secure storage.
class AuthService {
  AuthService({
    BackendSettingsStore? settingsStore,
    AuthTokenStore? tokenStore,
    http.Client? httpClient,
  }) : _settingsStore = settingsStore ?? SecureBackendSettingsStore(),
       _tokenStore = tokenStore ?? SecureAuthTokenStore(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static final AuthService instance = AuthService();

  final BackendSettingsStore _settingsStore;
  final AuthTokenStore _tokenStore;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<AuthUser> register({
    required String email,
    required String password,
  }) => _authenticate('register', email: email, password: password);

  Future<AuthUser> login({required String email, required String password}) =>
      _authenticate('login', email: email, password: password);

  Future<AuthUser> _authenticate(
    String action, {
    required String email,
    required String password,
  }) async {
    final response = await _send(
      action,
      body: {'email': email.trim(), 'password': password},
    );
    final data = _decodeResponse(response);
    final token = data['token'];
    final userJson = data['user'];
    if (token is! String || userJson is! Map<String, dynamic>) {
      throw const AuthException(
        'response.invalid',
        'Sunucudan geçersiz yanıt alındı.',
      );
    }
    final user = AuthUser.fromJson(userJson);
    await _tokenStore.saveToken(token);
    await _tokenStore.saveUserId(user.id);
    return user;
  }

  Future<bool> get hasStoredSession async =>
      (await _tokenStore.readToken())?.isNotEmpty ?? false;

  Future<String?> get storedUserId => _tokenStore.readUserId();

  Future<AuthUser?> currentUser() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) return null;

    final response = await _send('me', token: token, method: 'GET');
    if (response.statusCode == 401) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final error = data['error'];
        if (error is Map<String, dynamic> &&
            error['code'] == 'auth.session_invalid') {
          await _tokenStore.clearToken();
          return null;
        }
      } on FormatException {
        // Keep the token if the backend returned an unrelated or malformed 401.
      } on TypeError {
        // Keep the token if the backend returned an unrelated or malformed 401.
      }
    }
    final data = _decodeResponse(response);
    final userJson = data['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const AuthException(
        'response.invalid',
        'Sunucudan geçersiz yanıt alındı.',
      );
    }
    final user = AuthUser.fromJson(userJson);
    await _tokenStore.saveUserId(user.id);
    return user;
  }

  Future<String> userIdForRequests() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) {
      return UserIdentityService.getOrCreateUserId();
    }
    final userId = await _tokenStore.readUserId();
    if (userId == null || userId.isEmpty) {
      throw const AuthException(
        'session.expired',
        'Oturumunuz sona erdi. Yeniden giriş yapın.',
      );
    }
    return userId;
  }

  Future<Map<String, String>> authorizationHeaders() async {
    final token = await _tokenStore.readToken();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> logout() async {
    final token = await _tokenStore.readToken();
    try {
      if (token != null && token.isNotEmpty) {
        await _send('logout', token: token);
      }
    } catch (_) {
      // Always clear the local session so the user can leave the account.
    } finally {
      await _tokenStore.clearToken();
    }
  }

  Future<void> deleteAccount({required String guestUserId}) async {
    final token = await _tokenStore.readToken();
    final response = await _send(
      'delete-account',
      token: token,
      body: token == null || token.isEmpty ? {'userId': guestUserId} : const {},
    );
    try {
      _decodeResponse(response);
    } on AuthException catch (error) {
      if (error.code == 'auth.session_invalid') {
        await _tokenStore.clearToken();
      }
      rethrow;
    }
    await _tokenStore.clearToken();
  }

  Future<http.Response> _send(
    String endpoint, {
    String method = 'POST',
    String? token,
    Map<String, Object?>? body,
  }) async {
    final settings = await _settingsStore.load();
    final baseUrl = settings.isConfigured
        ? settings.baseUrl
        : BackendSettings.defaultBaseUrl;
    final uri = Uri.parse(baseUrl).resolve('/api/auth/$endpoint');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (method == 'POST') 'Content-Type': 'application/json',
      if (settings.apiKey.isNotEmpty) 'X-Api-Key': settings.apiKey,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final response = method == 'GET'
        ? await _httpClient
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15))
        : await _httpClient
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 15));
    return response;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const AuthException(
        'response.invalid',
        'Sunucudan geçersiz yanıt alındı.',
      );
    } on TypeError {
      throw const AuthException(
        'response.invalid',
        'Sunucudan geçersiz yanıt alındı.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'];
      final code = error is Map<String, dynamic>
          ? error['code']?.toString() ?? 'auth.failed'
          : 'auth.failed';
      throw AuthException(
        code,
        code == 'auth.invalid_credentials'
            ? 'E-posta veya şifre hatalı.'
            : code == 'auth.rate_limited'
            ? 'Çok fazla başarısız deneme. Bir süre sonra tekrar deneyin.'
            : code == 'auth.email_in_use'
            ? 'Bu e-posta adresiyle zaten bir hesap var.'
            : code == 'auth.email_invalid'
            ? 'Geçerli bir e-posta adresi girin.'
            : code == 'auth.password_invalid'
            ? 'Şifre en az 8, en fazla 128 karakter olmalı.'
            : 'İşlem tamamlanamadı. Bilgilerinizi kontrol edip tekrar deneyin.',
      );
    }
    return data;
  }

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
