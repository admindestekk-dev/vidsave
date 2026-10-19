import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subscription_screen.dart';

/// VidSave AdMob Reklam Yönetim Servisi
///
/// Google Play Store politikalarıyla uyumlu:
/// 1. Resmi Android Ödüllü Test Reklam Kimliği: `ca-app-pub-3940256099942544/5224354917`
/// 2. Akıllı Premium Filtresi:
///    - `isPremium == true` ise (Aylık 9,99 TL ödeyen üyeler): Reklam kodları tamamen bypass edilir,
///      hiçbir reklam gösterilmeden doğrudan indirme başlatılır.
///    - `isPremium == false` ise (Giriş yapmamış veya ücretsiz üyeler): Zorunlu ödüllü reklam oynatılır.
///      Kullanıcı reklamı sonuna kadar izlerse (`onUserEarnedReward`), indirme işlemi otomatik başlar.
class AdmobService {
  AdmobService._();
  static final AdmobService instance = AdmobService._();

  /// Google Resmi Test Cihazı Kimlikleri & Reklam Birim Kimlikleri
  /// iOS: ca-app-pub-3940256099942544/1712485313
  /// Android: ca-app-pub-3940256099942544/5224354917
  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    try {
      if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/1712485313';
      }
    } catch (_) {}
    return 'ca-app-pub-3940256099942544/5224354917';
  }

  RewardedAd? _rewardedAd;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _consentGathered = false;
  final List<VoidCallback> _pendingLoadedCallbacks = [];
  final List<VoidCallback> _pendingFailedCallbacks = [];

  /// AdMob SDK başlatma metodu (main.dart veya ilk ihtiyaçta çağrılır)
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await MobileAds.instance.initialize();
      // Tüm emülatörler ve test cihazları için otomatik test yapılandırması
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: <String>[],
        ),
      );
      _isInitialized = true;
      unawaited(gatherConsentIfRequired());
      loadRewardedAd();
    } catch (e) {
      debugPrint('AdmobService: MobileAds initialize error: $e');
    }
  }

  /// Avrupa Birliği (GDPR) ve UMP SDK Kullanıcı Rızası (Consent Form) Yönetimi
  ///
  /// Kullanıcı AB/AEA veya rıza gerektiren bir bölgedeyse Google'ın resmi
  /// onay formunu (Consent Form) ekrana getirir. Onay alındıktan sonra
  /// reklam motorunun başlatılmasını ve ödüllü reklamın güvenle yüklenmesini sağlar.
  Future<void> gatherConsentIfRequired() async {
    if (_consentGathered || isRunningInTest || kIsWeb) return;

    final completer = Completer<void>();
    final params = ConsentRequestParameters();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null) {
              debugPrint('AdmobService: UMP Form gösterim uyarısı: ${formError.message}');
            }
            _consentGathered = true;
            // Rıza verildikten sonra reklamı taze rıza parametreleriyle yükle
            loadRewardedAd();
            if (!completer.isCompleted) completer.complete();
          });
        },
        (FormError error) {
          debugPrint('AdmobService: UMP Consent Info güncelleme hatası: ${error.message}');
          _consentGathered = true;
          loadRewardedAd();
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e) {
      debugPrint('AdmobService: UMP SDK çalıştırma hatası: $e');
      _consentGathered = true;
      if (!completer.isCompleted) completer.complete();
    }

    // Arayüzün kilitlenmemesi için maksimum 4 saniye timeout tanınır
    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('AdmobService: UMP zaman aşımına uğradı, işleme devam ediliyor.');
      },
    );
  }

  /// Ödüllü reklamı önceden belleğe yükler (Pre-load)
  void loadRewardedAd({VoidCallback? onLoaded, VoidCallback? onFailed}) {
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
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(SubscriptionScreen.prefKeyIsPremium) ?? false;
    } catch (_) {
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
      debugPrint('AdmobService: Premium aktif. AdMob bypass edildi, indirme başlatılıyor.');
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
            debugPrint('AdmobService: Reklam yüklenemedi, kullanıcı bekletilmeden indirmeye devam ediliyor.');
            await onRewardEarned();
          }
        },
      );

      // Maksimum 4 saniye bekle; eğer ağ yavaşsa ve reklam yüklenemezse kullanıcıyı kilitleme
      unawaited(
        Future.delayed(const Duration(seconds: 4), () async {
          if (!completer.isCompleted) {
            completer.complete();
            debugPrint('AdmobService: Reklam yükleme zaman aşımı (4 sn), indirme başlatılıyor.');
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
        debugPrint('AdmobService: Kullanıcı reklamı sonuna kadar izledi, indirme başlatılıyor.');
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
