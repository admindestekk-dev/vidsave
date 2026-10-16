import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-configured Flask backend connection.
class BackendSettings {
  const BackendSettings({this.baseUrl = '', this.apiKey = ''});

  /// LAN default for physical devices; override at build time with --dart-define.
  /// 10.0.2.2 only works on the Android emulator, so physical-device debug
  /// builds default to this machine's Wi-Fi IPv4 address instead.
  static const defaultBaseUrl = String.fromEnvironment(
    'VIDSAVE_BACKEND_URL',
    defaultValue: 'http://10.192.215.20:8787',
  );

  final String baseUrl;
  final String apiKey;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Uri get baseUri {
    final normalized = baseUrl.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Backend adresi https:// sunucu-adresi:8787 biçiminde olmalı.',
      );
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  factory BackendSettings.fromInput({
    required String baseUrl,
    required String apiKey,
  }) {
    final candidate = BackendSettings(
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
    );
    final uri = candidate.baseUri;
    return BackendSettings(baseUrl: uri.origin, apiKey: candidate.apiKey);
  }
}

abstract interface class BackendSettingsStore {
  Future<BackendSettings> load();
  Future<void> save(BackendSettings settings);
}

/// Stores the backend URL and API key in platform encrypted storage.
class SecureBackendSettingsStore implements BackendSettingsStore {
  SecureBackendSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'vidsave.backend.base_url';
  static const _apiKeyKey = 'vidsave.backend.api_key';

  final FlutterSecureStorage _storage;

  @override
  Future<BackendSettings> load() async {
    final values = await Future.wait([
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _apiKeyKey),
    ]);
    final savedBaseUrl = values[0];
    return BackendSettings(
      baseUrl: savedBaseUrl == null || savedBaseUrl.isEmpty
          ? BackendSettings.defaultBaseUrl
          : savedBaseUrl,
      apiKey: values[1] ?? '',
    );
  }

  @override
  Future<void> save(BackendSettings settings) async {
    await _storage.write(key: _baseUrlKey, value: settings.baseUrl);
    if (settings.apiKey.isEmpty) {
      await _storage.delete(key: _apiKeyKey);
    } else {
      await _storage.write(key: _apiKeyKey, value: settings.apiKey);
    }
  }
}
