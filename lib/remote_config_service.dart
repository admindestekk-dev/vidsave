import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Firebase Remote Config Dinamik Kod ve Regex Yönetim Servisi
///
/// Google Play Store güncellemesine gerek kalmadan buluttan anlık olarak:
/// 1. `tiktok_regex`
/// 2. `instagram_regex`
/// 3. `facebook_regex`
/// 4. `twitter_regex`
/// 5. `pinterest_regex`
/// 6. `user_agent_string`
/// 7. `backup_api_url` (Python Backend Fallback URL)
/// parametrelerini yönetir.
class RemoteConfigService {
  RemoteConfigService._();

  static final RemoteConfigService instance = RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfig;
  bool _initialized = false;

  /// Yerel varsayılan (fallback) kurallar
  static const Map<String, dynamic> _defaultParameters = {
    'tiktok_regex':
        r'"download_url":"(.*?)"|"playAddr":\s*"([^"]+)"|"downloadAddr":\s*"([^"]+)"|"url":\s*"(https://[^"]*tiktokcdn\.com[^"]+\.mp4[^"]*)"',
    'instagram_regex':
        r'"download_url":"(.*?)"|<meta\s+property="og:video"\s+content="([^"]+)"|<meta\s+content="([^"]+)"\s+property="og:video"|"video_url":\s*"([^"]+)"',
    'facebook_regex':
        r'"download_url":"(.*?)"|"playable_url_quality_hd":\s*"([^"]+)"|"hd_src":\s*"([^"]+)"|"playable_url":\s*"([^"]+)"|"sd_src":\s*"([^"]+)"',
    'twitter_regex':
        r'"download_url":"(.*?)"|(https://video\.twimg\.com/[^"\\]+\.mp4[^"\\]*)|"video_url":\s*"([^"]+)"|<meta\s+property="og:video:url"\s+content="([^"]+)"',
    'pinterest_regex':
        r'"download_url":"(.*?)"|"url":\s*"(https://[^"]+\.mp4[^"]*)"|"url":\s*"(https://i\.pinimg\.com/originals/[^"]+)"',
    'user_agent_string':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'backup_api_url': '',
  };

  /// Bellekteki aktif konfigürasyon önbelleği
  final Map<String, String> _customOverrides = {};

  /// Firebase Remote Config servisini başlatır ve buluttan anlık çeker.
  Future<void> initialize({FirebaseRemoteConfig? remoteConfigInstance}) async {
    if (_initialized) return;

    if (remoteConfigInstance != null) {
      _remoteConfig = remoteConfigInstance;
      _initialized = true;
      return;
    }

    try {
      // Firebase Core ilklendirilmemişse güvenle dene
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // Zaten ilklendirilmiş veya test ortamında
      }

      _remoteConfig = FirebaseRemoteConfig.instance;

      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kDebugMode
              ? const Duration(seconds: 0)
              : const Duration(hours: 1),
        ),
      );

      await _remoteConfig!.setDefaults(_defaultParameters);
      await fetchAndActivate();
      _initialized = true;
      debugPrint('RemoteConfigService: Firebase Remote Config başarıyla hazırlandı.');
    } catch (e) {
      debugPrint('RemoteConfigService başlatma uyarısı (Varsayılan yerel kurallar kullanılacak): $e');
      _initialized = true;
    }
  }

  /// Buluttaki en güncel parametreleri çeker ve aktif eder
  Future<bool> fetchAndActivate() async {
    if (_remoteConfig == null) return false;
    try {
      final updated = await _remoteConfig!.fetchAndActivate();
      debugPrint('RemoteConfigService: fetchAndActivate tamamlandı (Güncelleme: $updated)');
      return updated;
    } catch (e) {
      debugPrint('RemoteConfigService fetch hatası: $e');
      return false;
    }
  }

  /// Parametreyi dinamik olarak okur (Bulut -> Yerel Fallback)
  String getString(String key) {
    if (_customOverrides.containsKey(key) && _customOverrides[key]!.isNotEmpty) {
      return _customOverrides[key]!;
    }

    if (_remoteConfig != null) {
      final val = _remoteConfig!.getString(key).trim();
      if (val.isNotEmpty) {
        return val;
      }
    }

    return (_defaultParameters[key] as String?) ?? '';
  }

  /// Test veya dinamik override için değer atama
  void setOverride(String key, String value) {
    _customOverrides[key] = value;
  }

  /// Override temizleme
  void clearOverrides() {
    _customOverrides.clear();
  }

  // Kolay erişim metotları
  String get tiktokRegex => getString('tiktok_regex');
  String get instagramRegex => getString('instagram_regex');
  String get facebookRegex => getString('facebook_regex');
  String get twitterRegex => getString('twitter_regex');
  String get pinterestRegex => getString('pinterest_regex');
  String get userAgent => getString('user_agent_string');
  String get backupApiUrl => getString('backup_api_url');
}
