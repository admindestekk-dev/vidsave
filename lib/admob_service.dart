import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'subscription_screen.dart';

/// VidSave AdMob rewarded-ad manager.
///
/// Uses Google's official demo ad units, which always serve test ads. Replace
/// them with the app's own ad unit IDs only when configuring a production
/// release; never click live ads while testing.
class AdmobService {
  AdmobService._();
  static final AdmobService instance = AdmobService._();

  /// Official Google demo ad units, used only for testing.
  static const Map<String, Map<String, String>> testAdUnitIds = {
    'android': {
      'banner': 'ca-app-pub-3940256099942544/6300978111',
      'interstitial': 'ca-app-pub-3940256099942544/1033173712',
      'rewarded': 'ca-app-pub-3940256099942544/5224354917',
      'native': 'ca-app-pub-3940256099942544/2247696110',
      'appOpen': 'ca-app-pub-3940256099942544/9257395921',
    },
    'ios': {
      'banner': 'ca-app-pub-3940256099942544/2934735716',
      'interstitial': 'ca-app-pub-3940256099942544/4411468910',
      'rewarded': 'ca-app-pub-3940256099942544/1712485313',
      'native': 'ca-app-pub-3940256099942544/3986624511',
      'appOpen': 'ca-app-pub-3940256099942544/5575463023',
    },
  };

  static const String umpTestDeviceId = String.fromEnvironment(
    'VIDSAVE_UMP_TEST_DEVICE_ID',
  );
  static const String umpDebugGeography = String.fromEnvironment(
    'VIDSAVE_UMP_DEBUG_GEOGRAPHY',
  );

  static DebugGeography? debugGeographyFor(String value) => switch (value) {
    'eea' => DebugGeography.debugGeographyEea,
    'regulated-us' => DebugGeography.debugGeographyRegulatedUsState,
    'other' => DebugGeography.debugGeographyOther,
    _ => null,
  };

  static String testAdUnitId(String format) {
    if (kIsWeb) return '';
    final platform = Platform.isIOS ? 'ios' : 'android';
    final adUnitId = testAdUnitIds[platform]?[format];
    if (adUnitId == null) {
      throw ArgumentError.value(format, 'format', 'Unsupported test ad format');
    }
    return adUnitId;
  }

  static String get rewardedAdUnitId {
    return testAdUnitId('rewarded');
  }

  RewardedAd? _rewardedAd;
  bool _isLoading = false;
  bool _isInitialized = false;
  Future<void>? _initialization;
  Future<void>? _consentUpdate;
  bool _consentGathered = false;
  bool _canRequestAds = false;
  final List<VoidCallback> _pendingLoadedCallbacks = [];
  final List<VoidCallback> _pendingFailedCallbacks = [];

  bool get isInitialized => _isInitialized;
  bool get canRequestAds => _canRequestAds;

  /// AdMob SDK başlatma metodu (main.dart veya ilk ihtiyaçta çağrılır)
  Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS) || isRunningInTest) {
      return;
    }
    final existingInitialization = _initialization;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }
    if (_isInitialized) return;

    final initialization = _initializeSdk();
    _initialization = initialization;
    await initialization;
  }

  Future<void> _initializeSdk() async {
    try {
      // Apply request configuration before SDK initialization and before the
      // first ad request.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: kDebugMode && umpTestDeviceId.isNotEmpty
              ? <String>[umpTestDeviceId]
              : const <String>[],
        ),
      );
      await MobileAds.instance.initialize();
      _isInitialized = true;
      await gatherConsentIfRequired();
      if (_canRequestAds) loadRewardedAd();
    } catch (e) {
      _isInitialized = false;
      debugPrint('AdmobService: MobileAds initialize error: $e');
    } finally {
      _initialization = null;
    }
  }

  /// Avrupa Birliği (GDPR) ve UMP SDK Kullanıcı Rızası (Consent Form) Yönetimi
  ///
  /// Kullanıcı AB/AEA veya rıza gerektiren bir bölgedeyse Google'ın resmi
  /// onay formunu (Consent Form) ekrana getirir. Onay alındıktan sonra
  /// reklam motorunun başlatılmasını ve ödüllü reklamın güvenle yüklenmesini sağlar.
  Future<void> gatherConsentIfRequired() async {
    if (_consentGathered) return;
    final pendingUpdate = _consentUpdate;
    if (pendingUpdate != null) {
      await pendingUpdate;
      return;
    }
    if (isRunningInTest || kIsWeb) {
      _consentGathered = true;
      _canRequestAds = true;
      return;
    }

    final completer = Completer<void>();
    _consentUpdate = completer.future;
    final debugGeography = debugGeographyFor(umpDebugGeography);
    final debugSettings =
        kDebugMode && umpTestDeviceId.isNotEmpty && debugGeography != null
        ? ConsentDebugSettings(
            testIdentifiers: <String>[umpTestDeviceId],
            debugGeography: debugGeography,
          )
        : null;
    final params = ConsentRequestParameters(
      consentDebugSettings: debugSettings,
    );

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          unawaited(() async {
            try {
              await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
                if (formError != null) {
                  debugPrint(
                    'AdmobService: UMP Form gösterim uyarısı: ${formError.message}',
                  );
                }
              });
              await _refreshConsentStatus();
            } catch (error, stackTrace) {
              debugPrint(
                'AdmobService: UMP form işlemi başarısız: $error\n$stackTrace',
              );
              await _refreshConsentStatus();
            } finally {
              _consentGathered = true;
              if (!completer.isCompleted) completer.complete();
              _consentUpdate = null;
            }
          }());
        },
        (FormError error) {
          debugPrint(
            'AdmobService: UMP Consent Info güncelleme hatası: ${error.message}',
          );
          unawaited(() async {
            try {
              await _refreshConsentStatus();
            } finally {
              _consentGathered = true;
              if (!completer.isCompleted) completer.complete();
              _consentUpdate = null;
            }
          }());
        },
      );
    } catch (e, stackTrace) {
      debugPrint('AdmobService: UMP SDK çalıştırma hatası: $e\n$stackTrace');
      await _refreshConsentStatus();
      _consentGathered = true;
      _consentUpdate = null;
      if (!completer.isCompleted) completer.complete();
    }

    await completer.future;
  }

  Future<void> _refreshConsentStatus() async {
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (error, stackTrace) {
      _canRequestAds = false;
      debugPrint(
        'AdmobService: UMP consent durumu okunamadı: $error\n$stackTrace',
      );
    }

    try {
      final requirement = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      privacyOptionsRequired.value =
          requirement == PrivacyOptionsRequirementStatus.required;
    } catch (error, stackTrace) {
      debugPrint(
        'AdmobService: UMP gizlilik seçeneği durumu okunamadı: $error\n$stackTrace',
      );
    }
  }

  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  Future<void> showPrivacyOptionsForm() async {
    await initialize();
    if (!privacyOptionsRequired.value) return;

    final completer = Completer<void>();
    try {
      await ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint(
            'AdmobService: Gizlilik tercihleri formu açılamadı: ${formError.message}',
          );
        }
        unawaited(() async {
          await _refreshConsentStatus();
          if (_canRequestAds) loadRewardedAd();
          if (!completer.isCompleted) completer.complete();
        }());
      });
    } catch (error, stackTrace) {
      debugPrint(
        'AdmobService: Gizlilik tercihleri açılamadı: $error\n$stackTrace',
      );
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
    await completer.future;
  }

  Future<bool> isPrivacyOptionsRequired() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS) || isRunningInTest) {
      return false;
    }
    await initialize();
    if (!_consentGathered) await gatherConsentIfRequired();
    await _refreshConsentStatus();
    return privacyOptionsRequired.value;
  }

  /// Ödüllü reklamı önceden belleğe yükler (Pre-load)
  void loadRewardedAd({VoidCallback? onLoaded, VoidCallback? onFailed}) {
    if (!_isInitialized || !_canRequestAds) {
      onFailed?.call();
      return;
    }
    if (_rewardedAd != null) {
      onLoaded?.call();
      return;
    }
    if (_isLoading) {
      if (onLoaded != null) _pendingLoadedCallbacks.add(onLoaded);
      if (onFailed != null) _pendingFailedCallbacks.add(onFailed);
      return;
    }
    _isLoading = true;
    if (onLoaded != null) _pendingLoadedCallbacks.add(onLoaded);
    if (onFailed != null) _pendingFailedCallbacks.add(onFailed);

    try {
      RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _isLoading = false;
            debugPrint('AdmobService: Ödüllü reklam başarıyla yüklendi.');
            final callbacks = List<VoidCallback>.from(_pendingLoadedCallbacks);
            _pendingLoadedCallbacks.clear();
            _pendingFailedCallbacks.clear();
            for (final cb in callbacks) {
              cb();
            }
          },
          onAdFailedToLoad: (error) {
            _rewardedAd = null;
            _isLoading = false;
            debugPrint('AdmobService: Ödüllü reklam yükleme hatası: $error');
            final callbacks = List<VoidCallback>.from(_pendingFailedCallbacks);
            _pendingLoadedCallbacks.clear();
            _pendingFailedCallbacks.clear();
            for (final cb in callbacks) {
              cb();
            }
          },
        ),
      );
    } catch (e) {
      _isLoading = false;
      debugPrint('AdmobService: loadRewardedAd exception: $e');
      final callbacks = List<VoidCallback>.from(_pendingFailedCallbacks);
      _pendingLoadedCallbacks.clear();
      _pendingFailedCallbacks.clear();
      for (final cb in callbacks) {
        cb();
      }
    }
  }

  /// Kullanıcının aktif Premium üyeliği olup olmadığını shared_preferences üzerinden sorgular
  Future<bool> checkIsPremium() async {
    try {
      return await SubscriptionScreen.readPremiumStatus();
    } catch (error, stackTrace) {
      debugPrint('Premium durumu okunamadı: $error\n$stackTrace');
      return false;
    }
  }

  /// Premium Filtreli İndirme Tetikleyicisi
  ///
  /// - `isPremium == true` ise: AdMob'u tamamen bypass ederek doğrudan `onRewardEarned` callback'ini çağırır.
  /// - `isPremium == false` ise: Ödüllü reklamı gösterir. Kullanıcı reklamı sonuna kadar izlediğinde
  ///   (`onUserEarnedReward`), indirmeyi başlatır.
  /// - Test ortamlarında ve web platformunda indirmeyi doğrudan güvenle çalıştırır.
  bool disableAdsForTesting = false;

  /// Test veya widget ortamı tespiti (headless testlerde reklam beklemesini engeller)
  bool get isRunningInTest {
    if (disableAdsForTesting) return true;
    try {
      final binding = WidgetsBinding.instance;
      final typeStr = binding.runtimeType.toString().toLowerCase();
      if (typeStr.contains('test') ||
          typeStr.contains('automated') ||
          typeStr.contains('fake')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> showRewardedAdOrBypass({
    required FutureOr<void> Function() onRewardEarned,
    VoidCallback? onAdDismissedWithoutReward,
  }) async {
    // Test veya widget ortamı kontrolü
    if (isRunningInTest || kIsWeb) {
      debugPrint('AdmobService: Test ortamı tespit edildi. Reklam atlandı.');
      await onRewardEarned();
      return;
    }

    final isPremium = await checkIsPremium();

    // 1. PREMIUM BYPASS: Ücretli abone ise reklamı tamamen atla
    if (isPremium) {
      debugPrint(
        'AdmobService: Premium aktif. AdMob bypass edildi, indirme başlatılıyor.',
      );
      await onRewardEarned();
      return;
    }

    await initialize();
    if (!_isInitialized) {
      await onRewardEarned();
      return;
    }

    // 2. ÜCRETSİZ / GİRİŞ YAPMAMIŞ KULLANICI:
    // GDPR / UMP kullanıcı rızası henüz alınmadıysa öncelikle rıza formunu tamamla
    if (!_consentGathered) {
      await gatherConsentIfRequired();
    }

    if (_rewardedAd == null) {
      // Reklam önceden yüklenmemişse yüklemeyi dene (azami 4 sn bekle)
      // Kullanıcı deneyimi için zaman aşımına uğrarsa indirmeye devam et
      final completer = Completer<void>();
      loadRewardedAd(
        onLoaded: () {
          if (!completer.isCompleted) {
            completer.complete();
            _presentRewardedAd(
              onRewardEarned: onRewardEarned,
              onAdDismissedWithoutReward: onAdDismissedWithoutReward,
            );
          }
        },
        onFailed: () async {
          if (!completer.isCompleted) {
            completer.complete();
            debugPrint(
              'AdmobService: Reklam yüklenemedi, kullanıcı bekletilmeden indirmeye devam ediliyor.',
            );
            await onRewardEarned();
          }
        },
      );

      // Maksimum 4 saniye bekle; eğer ağ yavaşsa ve reklam yüklenemezse kullanıcıyı kilitleme
      unawaited(
        Future.delayed(const Duration(seconds: 4), () async {
          if (!completer.isCompleted) {
            completer.complete();
            debugPrint(
              'AdmobService: Reklam yükleme zaman aşımı (4 sn), indirme başlatılıyor.',
            );
            await onRewardEarned();
          }
        }),
      );
      return;
    }

    _presentRewardedAd(
      onRewardEarned: onRewardEarned,
      onAdDismissedWithoutReward: onAdDismissedWithoutReward,
    );
  }

  void _presentRewardedAd({
    required FutureOr<void> Function() onRewardEarned,
    VoidCallback? onAdDismissedWithoutReward,
  }) {
    final ad = _rewardedAd;
    if (ad == null) {
      onRewardEarned();
      return;
    }

    bool earnedReward = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd(); // Bir sonraki indirme için reklamı hemen arka planda hazırla
        if (!earnedReward) {
          onAdDismissedWithoutReward?.call();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AdmobService: Reklam gösterilemedi: $error');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        // Reklam gösterim hatasında da indirmeyi bloke etme
        onRewardEarned();
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        debugPrint(
          'AdmobService: Kullanıcı reklamı sonuna kadar izledi, indirme başlatılıyor.',
        );
        earnedReward = true;
        await onRewardEarned();
      },
    );
  }

  /// Bellek yönetimi: Kaynakları temizle
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}
