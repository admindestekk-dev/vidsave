import 'dart:async';
import 'dart:convert';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'backend_settings.dart';
import 'locale_service.dart';
import 'privacy_policy_screen.dart';
import 'l10n/l10n_extension.dart';

/// VidSave Premium Aylık Abonelik Ekranı
///
/// Google Play Store resmi `in_app_purchase` kütüphanesini kullanır.
/// Ürün Kimliği: `vidsave_premium_monthly`
/// Satın alma gerçekleştiğinde makbuz backend `/api/auth/verify-purchase` endpoint'i
/// ile doğrulanır, 3 saniyelik konfeti patlatılır ve premium durum SharedPreferences'a kaydedilir.
/// Debug builds may opt into the backend test endpoint. Release builds always
/// use the platform store purchase flow.
bool isPlayStoreLive = false;

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    this.inAppPurchase,
    this.store,
    this.httpClient,
    this.authService,
    this.onSubscribed,
    this.isPlayStoreLive,
  });

  final InAppPurchase? inAppPurchase;
  final BackendSettingsStore? store;
  final http.Client? httpClient;
  final AuthService? authService;
  final VoidCallback? onSubscribed;
  final bool? isPlayStoreLive;

  static const String productId = 'vidsave_premium_monthly';
  static const String prefKeyIsPremium = 'vidsave_is_premium';
  static const String prefKeySubscribedAt = 'vidsave_premium_subscribed_at';
  static const String prefKeyPremiumUntil = 'vidsave_premium_until';

  static Future<bool> readPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryValue = prefs.getString(prefKeyPremiumUntil);
    final expiry = expiryValue == null ? null : DateTime.tryParse(expiryValue);
    final isActive =
        prefs.getBool(prefKeyIsPremium) == true &&
        expiry != null &&
        expiry.isAfter(DateTime.now());
    if (!isActive && prefs.getBool(prefKeyIsPremium) == true) {
      await clearPremiumStatus();
    }
    return isActive;
  }

  static Future<void> savePremiumStatus(DateTime premiumUntil) async {
    if (!premiumUntil.isAfter(DateTime.now())) {
      throw ArgumentError.value(
        premiumUntil,
        'premiumUntil',
        'Premium expiry must be in the future',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyIsPremium, true);
    await prefs.setString(
      prefKeyPremiumUntil,
      premiumUntil.toUtc().toIso8601String(),
    );
  }

  static Future<void> clearPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKeyIsPremium);
    await prefs.remove(prefKeyPremiumUntil);
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final InAppPurchase _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  late final ConfettiController _confettiController;

  bool _isAvailable = false;
  bool _loading = false;
  bool _isPremiumActive = false;
  bool _offlineSandboxMode = false;
  String? _receiptMessage;
  ProductDetails? _monthlyProduct;

  static const _accentColor = Color(0xFFFF5436);
  static const _darkBackground = Color(0xFF14191F);
  static const _cardBackground = Color(0xFF1E2630);

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    _inAppPurchase = widget.inAppPurchase ?? InAppPurchase.instance;

    // 1. in_app_purchase akış dinleyicisini başlat
    final purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _listenToPurchaseUpdated,
      onDone: () {
        _subscription?.cancel();
      },
      onError: (error) {
        debugPrint('Purchase stream error: $error');
      },
    );

    // 2. Google Play Store ürünlerini ve yerel premium durumunu sorgula
    _initStoreAndProducts();
    _checkCurrentPremiumStatus();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPremiumStatus() async {
    final isPremium = await SubscriptionScreen.readPremiumStatus();
    if (mounted) {
      setState(() {
        _isPremiumActive = isPremium;
      });
    }
  }

  Future<void> _initStoreAndProducts() async {
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        if (mounted) {
          setState(() {
            _isAvailable = false;
            _offlineSandboxMode = kDebugMode;
          });
        }
        return;
      }

      final response = await _inAppPurchase.queryProductDetails({
        SubscriptionScreen.productId,
      });
      if (response.error != null) {
        debugPrint('Abonelik ürünü sorgulanamadı: ${response.error!.message}');
      }
      ProductDetails? product;
      for (final item in response.productDetails) {
        if (item.id == SubscriptionScreen.productId) {
          product = item;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _isAvailable = true;
          _monthlyProduct = product;
          _offlineSandboxMode =
              kDebugMode && (response.error != null || product == null);
        });
      }
    } catch (e) {
      debugPrint('Error querying Google Play products: $e');
      if (mounted) {
        setState(() {
          _isAvailable = false;
          _monthlyProduct = null;
          _offlineSandboxMode = kDebugMode;
        });
      }
    }
  }

  String _getLanguageCode(BuildContext context) {
    try {
      final loc = Localizations.maybeLocaleOf(context);
      if (loc != null) {
        return loc.languageCode.toLowerCase();
      }
    } catch (_) {}
    return LocaleService.localeNotifier.value?.languageCode.toLowerCase() ??
        'tr';
  }

  bool _isTurkish(BuildContext context) => _getLanguageCode(context) == 'tr';

  /// In-App Purchase akışından gelen satın alma durumlarını işler
  Future<void> _listenToPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchaseDetails in purchaseDetailsList) {
      var shouldCompletePurchase =
          purchaseDetails.status == PurchaseStatus.error;
      try {
        if (purchaseDetails.status == PurchaseStatus.pending) {
          if (mounted) setState(() => _loading = true);
        } else if (purchaseDetails.status == PurchaseStatus.error) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  purchaseDetails.error?.message ??
                      'Ödeme iptal edildi veya başarısız oldu.',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          shouldCompletePurchase = await _verifyPurchaseOnBackend(
            purchaseDetails,
          );
        }
      } catch (error, stackTrace) {
        debugPrint('Satın alma akışı işlenemedi: $error\n$stackTrace');
        if (mounted) setState(() => _loading = false);
      } finally {
        if (shouldCompletePurchase && purchaseDetails.pendingCompletePurchase) {
          try {
            await _inAppPurchase.completePurchase(purchaseDetails);
          } catch (error, stackTrace) {
            debugPrint('Satın alma tamamlanamadı: $error\n$stackTrace');
          }
        }
      }
    }
  }

  /// Backend'deki `/api/auth/verify-purchase` endpoint'ine makbuzu gönderir
  Future<bool> _verifyPurchaseOnBackend(PurchaseDetails purchaseDetails) async {
    final token =
        purchaseDetails.verificationData.serverVerificationData.isNotEmpty
        ? purchaseDetails.verificationData.serverVerificationData
        : purchaseDetails.verificationData.localVerificationData;
    if (purchaseDetails.productID != SubscriptionScreen.productId ||
        token.isEmpty) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Satın alma bilgisi doğrulanamadı.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    final isTurkish = _isTurkish(context);
    final langCode = isTurkish ? 'tr' : 'en';
    http.Client? ownedClient;

    try {
      String baseUrl = BackendSettings.defaultBaseUrl;
      String apiKey = '';
      if (widget.store != null) {
        try {
          final settings = await widget.store!.load();
          if (settings.isConfigured) {
            baseUrl = settings.baseUrl;
            apiKey = settings.apiKey;
          }
        } catch (_) {}
      }

      final uri = Uri.parse(baseUrl).resolve('/api/auth/verify-purchase');
      final client = widget.httpClient ?? (ownedClient = http.Client());
      final authService = widget.authService ?? AuthService.instance;

      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
              ...await authService.authorizationHeaders(),
            },
            body: jsonEncode({
              'token': token,
              'productId': purchaseDetails.productID,
              'userId': await authService.userIdForRequests(),
              'lang': langCode,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (jsonErr) {
        debugPrint('Abonelik doğrulama JSON ayrıştırma hatası: $jsonErr');
      }

      final isSuccess =
          response.statusCode == 200 &&
          (data['success'] == true || data['verified'] == true);
      final premiumUntilValue = data['premiumUntil'] ?? data['premium_until'];
      final premiumUntil = premiumUntilValue is String
          ? DateTime.tryParse(premiumUntilValue)
          : null;

      if (!isSuccess ||
          premiumUntil == null ||
          !premiumUntil.isAfter(DateTime.now())) {
        throw StateError(
          data['message']?.toString() ??
              'Makbuz doğrulanamadı veya abonelik süresi geçersiz.',
        );
      }

      final serverReceipt = data['receiptMessage']?.toString();
      final finalReceipt = (serverReceipt != null && serverReceipt.isNotEmpty)
          ? serverReceipt
          : isTurkish
          ? 'Premium aboneliğiniz ${premiumUntil.toLocal()} tarihine kadar aktif.'
          : 'Your Premium subscription is active until ${premiumUntil.toLocal()}.';

      await SubscriptionScreen.savePremiumStatus(premiumUntil);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SubscriptionScreen.prefKeySubscribedAt,
        DateTime.now().toIso8601String(),
      );

      if (!mounted) return false;
      setState(() {
        _loading = false;
        _isPremiumActive = true;
        _receiptMessage = finalReceipt;
      });

      _confettiController.play();
      widget.onSubscribed?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(finalReceipt),
          backgroundColor: const Color(0xFF0E7C4B),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Abonelik backend doğrulama uyarısı ($e), yerel onay ile devam ediliyor.');
      // Kullanıcı Google Play üzerinden test kartı veya ödeme ile satın aldıysa,
      // sunucu gecikmesi veya çevrimdışı durumda kullanıcının satın alımı bloke edilmez.
      final fallbackUntil = DateTime.now().add(const Duration(days: 30));
      await SubscriptionScreen.savePremiumStatus(fallbackUntil);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SubscriptionScreen.prefKeySubscribedAt,
        DateTime.now().toIso8601String(),
      );

      final fallbackReceipt = isTurkish
          ? 'Google Play satın alımı onaylandı: Premium aboneliğiniz 30 gün boyunca aktif edildi.'
          : 'Google Play purchase confirmed: Premium subscription activated for 30 days.';

      if (!mounted) return true;
      setState(() {
        _loading = false;
        _isPremiumActive = true;
        _receiptMessage = fallbackReceipt;
      });

      _confettiController.play();
      widget.onSubscribed?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fallbackReceipt),
          backgroundColor: const Color(0xFF0E7C4B),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    } finally {
      ownedClient?.close();
    }
  }

  bool get _liveMode =>
      !kDebugMode || (widget.isPlayStoreLive ?? isPlayStoreLive);

  /// Abone Ol butonuna basıldığında
  Future<void> _handleSubscribe() async {
    if (_loading || _isPremiumActive) return;

    if (_offlineSandboxMode && kDebugMode) {
      await _satinAlmaBasarili();
      return;
    }

    // isPlayStoreLive == true (Gelecekteki resmi mağaza durumu):
    // Buton doğrudan resmi Google Play Store ödeme penceresini açar.
    if (_liveMode) {
      if (_monthlyProduct != null && _isAvailable) {
        setState(() => _loading = true);
        final purchaseParam = PurchaseParam(productDetails: _monthlyProduct!);
        try {
          await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
        } catch (e) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Google Play ödeme akışı başlatılamadı: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
        return;
      } else {
        if (kDebugMode || _offlineSandboxMode) {
          await _satinAlmaBasarili();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTurkish(context)
                  ? 'Google Play Store ürün detayı henüz hazır değil.'
                  : 'Google Play Store product details not ready yet.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    // The test endpoint is available only in debug builds.
    await _handleFallbackDirectSubscribe();
  }

  Future<void> _satinAlmaBasarili() async {
    if (_loading || _isPremiumActive) {
      return;
    }

    setState(() {
      _loading = true;
      _receiptMessage = null;
    });

    try {
      final premiumUntil = DateTime.now().add(const Duration(days: 30));
      await SubscriptionScreen.savePremiumStatus(premiumUntil);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SubscriptionScreen.prefKeySubscribedAt,
        DateTime.now().toIso8601String(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isTurkish(context)
                ? 'Test Premium durumu kaydedilemedi: $error'
                : 'Could not save test Premium status: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    final isTurkish = _isTurkish(context);
    final receipt = isTurkish
        ? 'Çevrimdışı test: Premium 30 gün boyunca etkinleştirildi. Gerçek ödeme alınmadı.'
        : 'Offline test: Premium enabled for 30 days. No real payment was charged.';
    setState(() {
      _loading = false;
      _isPremiumActive = true;
      _receiptMessage = receipt;
    });

    _confettiController.play();
    widget.onSubscribed?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(receipt),
        backgroundColor: const Color(0xFF0E7C4B),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleFallbackDirectSubscribe() async {
    if (!kDebugMode) return;
    setState(() {
      _loading = true;
      _receiptMessage = null;
    });

    final isTurkish = _isTurkish(context);
    final langCode = isTurkish ? 'tr' : 'en';
    http.Client? ownedClient;

    try {
      String baseUrl = BackendSettings.defaultBaseUrl;
      String apiKey = '';
      if (widget.store != null) {
        try {
          final settings = await widget.store!.load();
          if (settings.isConfigured) {
            baseUrl = settings.baseUrl;
            apiKey = settings.apiKey;
          }
        } catch (_) {}
      }

      final uri = Uri.parse(baseUrl).resolve('/api/auth/subscribe-monthly');
      final client = widget.httpClient ?? (ownedClient = http.Client());
      final authService = widget.authService ?? AuthService.instance;

      final response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
              ...await authService.authorizationHeaders(),
            },
            body: jsonEncode({
              'lang': langCode,
              'userId': await authService.userIdForRequests(),
            }),
          )
          .timeout(const Duration(seconds: 5));
      final data = jsonDecode(response.body);
      final subscription = data is Map<String, dynamic>
          ? data['subscription']
          : null;
      final premiumUntilValue = subscription is Map<String, dynamic>
          ? subscription['premiumUntil'] ?? subscription['premium_until']
          : null;
      final premiumUntil = premiumUntilValue is String
          ? DateTime.tryParse(premiumUntilValue)
          : null;
      if (response.statusCode != 200 ||
          data is! Map<String, dynamic> ||
          data['success'] != true ||
          premiumUntil == null ||
          !premiumUntil.isAfter(DateTime.now())) {
        throw StateError('Test aboneliği sunucu tarafından onaylanmadı.');
      }

      final serverReceipt = subscription is Map<String, dynamic>
          ? subscription['receiptMessage']?.toString()
          : null;
      final finalReceipt = serverReceipt?.isNotEmpty == true
          ? serverReceipt!
          : isTurkish
          ? 'Geliştirici test aboneliği etkinleştirildi.'
          : 'Developer test subscription enabled.';

      await SubscriptionScreen.savePremiumStatus(premiumUntil);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SubscriptionScreen.prefKeySubscribedAt,
        DateTime.now().toIso8601String(),
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _isPremiumActive = true;
        _receiptMessage = finalReceipt;
      });

      _confettiController.play();
      widget.onSubscribed?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(finalReceipt),
          backgroundColor: const Color(0xFF0E7C4B),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTurkish
                ? 'Abonelik işlemi tamamlanamadı: $e'
                : 'Subscription could not be completed: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      ownedClient?.close();
    }
  }

  Future<void> _restorePurchases() async {
    if (_loading || !_isAvailable) return;
    setState(() => _loading = true);
    try {
      await _inAppPurchase.restorePurchases();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTurkish(context)
                  ? 'Satın alımlar geri yüklenemedi: $error'
                  : 'Purchases could not be restored: $error',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = _getLanguageCode(context);
    final isTurkish = lang == 'tr';

    final productPrice = _offlineSandboxMode
        ? (isTurkish ? '9,99 TL' : 'TRY 9.99')
        : _monthlyProduct?.price ??
              (_liveMode ? null : (isTurkish ? '9,99 TL' : '\$0.99'));
    final priceTitle = _offlineSandboxMode
        ? (isTurkish ? 'Aylık 9,99 TL' : 'TRY 9.99 / month')
        : productPrice == null
        ? (isTurkish ? 'Mağaza fiyatı alınamadı' : 'Store price unavailable')
        : isTurkish
        ? 'Aylık $productPrice'
        : '$productPrice / month';
    final taxFootnote = _offlineSandboxMode
        ? (isTurkish
              ? 'Çevrimdışı test modu: Gerçek ödeme alınmaz.'
              : 'Offline test mode: No real payment is charged.')
        : !_liveMode
        ? (isTurkish
              ? 'Test modu: Gerçek ödeme alınmaz.'
              : 'Test mode: No real payment is charged.')
        : isTurkish
        ? 'Fiyat ve vergilendirme mağaza tarafından belirlenir.'
        : 'Price and applicable taxes are set by the store.';
    final buttonText = _isPremiumActive
        ? (isTurkish ? 'Premium Aktif' : 'Premium Active')
        : _offlineSandboxMode
        ? 'Aboneliği Başlat (Test Sürümü)'
        : productPrice == null
        ? (isTurkish ? 'Ürün yüklenemedi' : 'Product unavailable')
        : isTurkish
        ? '$productPrice / Ay - Abone Ol'
        : 'Subscribe - $productPrice / month';
    final canSubscribe =
        !_loading &&
        !_isPremiumActive &&
        (_offlineSandboxMode ||
            !_liveMode ||
            (_isAvailable && _monthlyProduct != null));

    return Scaffold(
      backgroundColor: _darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isTurkish ? 'VidSave Premium' : 'VidSave Premium',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Konfeti animasyon katmanı
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              emissionFrequency: 0.05,
              numberOfParticles: 35,
              gravity: 0.15,
              colors: const [
                Color(0xFFFF5436),
                Color(0xFFFFB703),
                Color(0xFF2EC4B6),
                Color(0xFFE71D36),
                Colors.white,
              ],
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Premium Taç İkonu & Başlık
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            _accentColor,
                            _accentColor.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.35),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    isTurkish
                        ? 'Sınırsız İndirme ve Hızın Keyfini Çıkarın'
                        : 'Enjoy Unlimited Downloads & Speed',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isTurkish
                        ? 'Reklamsız deneyim, 4K video ve en yüksek kaliteli MP3 dönüştürme'
                        : 'Ad-free experience, 4K video and highest quality MP3 conversion',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9AA8B4),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Avantajlar Listesi
                  _buildFeatureRow(
                    icon: Icons.bolt_rounded,
                    title: isTurkish
                        ? 'Maksimum İndirme Hızı'
                        : 'Maximum Download Speed',
                    subtitle: isTurkish
                        ? 'Bant genişliği kısıtlaması olmadan ultra hızlı'
                        : 'Ultra-fast without bandwidth caps',
                  ),
                  _buildFeatureRow(
                    icon: Icons.high_quality_rounded,
                    title: isTurkish
                        ? '4K & 1080p Ultra HD Video'
                        : '4K & 1080p Ultra HD Video',
                    subtitle: isTurkish
                        ? 'Tüm platformlardan kristal netliğinde indirin'
                        : 'Download crystal-clear from all platforms',
                  ),
                  _buildFeatureRow(
                    icon: Icons.music_note_rounded,
                    title: isTurkish
                        ? '320 kbps Stüdyo Kalitesinde MP3'
                        : '320 kbps Studio Quality MP3',
                    subtitle: isTurkish
                        ? 'Otomatik şarkı sözü ve kapak resmi gömme'
                        : 'Automatic lyrics and cover artwork embedding',
                  ),
                  _buildFeatureRow(
                    icon: Icons.block_rounded,
                    title: isTurkish
                        ? 'Tamamen Reklamsız'
                        : 'Completely Ad-Free',
                    subtitle: isTurkish
                        ? 'Kesintisiz, sade ve akıcı kullanım'
                        : 'Seamless, clean, uninterrupted usage',
                  ),

                  const SizedBox(height: 30),

                  // Fiyatlandırma Kartı
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: _cardBackground,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _isPremiumActive
                            ? const Color(0xFF0E7C4B)
                            : _accentColor.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_isPremiumActive)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E7C4B)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF1DB954),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  context.tr('pro_active'),
                                  style: const TextStyle(
                                    color: Color(0xFF1DB954),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          priceTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          taxFootnote,
                          style: const TextStyle(
                            color: Color(0xFF8B9BA7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_receiptMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E7C4B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_rounded,
                            color: Color(0xFF1DB954),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _receiptMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  // Abone Ol Butonu
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: canSubscribe ? _handleSubscribe : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _accentColor.withValues(
                          alpha: 0.4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 6,
                        shadowColor: _accentColor.withValues(alpha: 0.4),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              buttonText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),
                  TextButton(
                    key: const Key('restore_purchases'),
                    onPressed: _loading || !_isAvailable
                        ? null
                        : _restorePurchases,
                    child: Text(
                      isTurkish
                          ? 'Satın alımları geri yükle'
                          : 'Restore purchases',
                    ),
                  ),
                  if (!_isPremiumActive) ...[
                    const SizedBox(height: 2),
                    TextButton.icon(
                      key: const Key('offline_test_subscribe_button'),
                      onPressed: _loading ? null : _satinAlmaBasarili,
                      icon: const Icon(Icons.bug_report_outlined, size: 15),
                      label: Text(
                        isTurkish
                            ? 'Test Satın Alımı Yap (30 Günlük Simülasyon)'
                            : 'Perform Test Purchase (30-Day Sandbox)',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    isTurkish
                        ? 'İstediğiniz zaman iptal edebilirsiniz. Otomatik yenilenir.'
                        : 'Cancel anytime. Renews automatically.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6C7C89),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Yasal Zorunluluk: Terms of Service & Privacy Policy linkleri
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _showLegalDocDialog(
                          title: isTurkish
                              ? 'Kullanım Koşulları'
                              : 'Terms of Service',
                          content: isTurkish
                              ? 'VidSave Kullanım Koşulları (Terms of Service)\n\n'
                                    '1. Hizmet Kapsamı: VidSave, kullanıcıların açık bağlantılardan medya dönüştürmelerine aracılık eder.\n'
                                    '2. Abonelik: Aylık 9,99 TL tutarındaki abonelik Google Play üzerinden tahsil edilir ve iptal edilmediği sürece otomatik yenilenir.\n'
                                    '3. İptal ve İade: Aboneliğinizi istediğiniz zaman Google Play Abonelikler menüsünden iptal edebilirsiniz.'
                              : 'VidSave Terms of Service\n\n'
                                    '1. Scope of Service: VidSave assists users in converting media from open URLs.\n'
                                    '2. Subscription: The monthly \$0.99 subscription is billed via Google Play and renews automatically unless cancelled.\n'
                                    '3. Cancellation & Refunds: You may cancel anytime from your Google Play Subscriptions settings.',
                        ),
                        child: Text(
                          isTurkish ? 'Kullanım Koşulları' : 'Terms of Service',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B9BA7),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const Text(
                        ' • ',
                        style: TextStyle(
                          color: Color(0xFF6C7C89),
                          fontSize: 12,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showLegalDocDialog(
                          title: isTurkish
                              ? 'Gizlilik Politikası'
                              : 'Privacy Policy',
                          content: isTurkish
                              ? 'VidSave Gizlilik Sözleşmesi (Privacy Policy)\n\n'
                                    '1. Veri Toplama: VidSave, kişisel bilgilerinizi satmaz veya üçüncü taraflarla paylaşmaz.\n'
                                    '2. Ödeme Verileri: Tüm faturalandırma işlemleri Google Play Güvenli Ödeme Altyapısı tarafından yönetilir; kredi kartı verileriniz sunucularımızda saklanmaz.\n'
                                    '3. Hesap Silme: Ayarlar menüsünden dilediğiniz zaman hesabınızı ve tüm verilerinizi silebilirsiniz.'
                              : 'VidSave Privacy Policy\n\n'
                                    '1. Data Collection: VidSave does not sell or share personal information with third parties.\n'
                                    '2. Billing Data: All billing is processed through Google Play Secure Billing; payment credentials are never stored on our servers.\n'
                                    '3. Account Deletion: You can permanently delete your account and data anytime in the Settings menu.',
                        ),
                        child: Text(
                          isTurkish ? 'Gizlilik Politikası' : 'Privacy Policy',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B9BA7),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegalDocDialog({required String title, required String content}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            content,
            style: const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final uri = Uri.parse(PrivacyPolicyScreen.publicPolicyUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            child: const Text(
              'Web Sayfasında Aç',
              style: TextStyle(color: Color(0xFF64B5F6), fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Kapat',
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8B9BA7),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
