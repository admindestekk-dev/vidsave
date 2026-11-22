import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';
import 'services/ad_shield_service.dart';
import 'subscription_screen.dart';

/// AdMob ve Google Play politikalarına tam uyumlu standart Banner Reklam Bileşeni.
///
/// Özellikler:
/// - Premium kullanıcılar için reklam isteği göndermez ve tamamen gizlenir.
/// - Test ve Web ortamlarında çökmeyi önler (`SizedBox.shrink()` döner).
/// - İçerikle karışmaması için net bir reklam etiketi ("REKLAM") ve ayracı içerir (Politika gereksinimi).
/// - Widget bellekten atıldığında `BannerAd` kaynağını güvenle dispose eder.
class AdmobBannerWidget extends StatefulWidget {
  const AdmobBannerWidget({
    super.key,
    this.adSize = AdSize.banner,
    this.showBadge = true,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
  });

  final AdSize adSize;
  final bool showBadge;
  final EdgeInsetsGeometry margin;

  @override
  State<AdmobBannerWidget> createState() => _AdmobBannerWidgetState();
}

class _AdmobBannerWidgetState extends State<AdmobBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isPremium = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    SubscriptionScreen.premiumStatusChanges.addListener(_onPremiumStatusChanged);
    _checkPremiumAndLoad();
  }

  void _onPremiumStatusChanged() {
    if (SubscriptionScreen.premiumStatusChanges.value == true) {
      _loadGeneration++;
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) {
        setState(() {
          _isPremium = true;
          _isLoaded = false;
        });
      }
    } else {
      unawaited(_checkPremiumAndLoad());
    }
  }

  Future<void> _checkPremiumAndLoad() async {
    final generation = ++_loadGeneration;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (AdmobService.instance.isRunningInTest) return;

    final isPrem = await AdmobService.instance.checkIsPremium();
    final isBlocked = await AdShieldService.instance.isAdBlocked();
    if (!mounted || generation != _loadGeneration) return;
    if (isPrem || isBlocked) {
      setState(() {
        _isPremium = true;
        _isLoaded = false;
      });
      _bannerAd?.dispose();
      _bannerAd = null;
      return;
    }
    if (_isPremium) setState(() => _isPremium = false);
    if (_bannerAd != null) return;

    await AdmobService.instance.initialize();
    if (!mounted || generation != _loadGeneration ||
        await AdmobService.instance.checkIsPremium()) {
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    if (!AdmobService.instance.isInitialized ||
        !AdmobService.instance.canRequestAds) {
      return;
    }

    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd?.dispose();
    final ad = BannerAd(
      adUnitId: AdmobService.bannerAdUnitId,
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdClicked: (ad) {
          debugPrint('AdmobBannerWidget: Banner tıklandı, AdShieldService kaydı alınıyor.');
          AdShieldService.instance.registerAdClick().then((newlyBlocked) {
            if (newlyBlocked && mounted) {
              setState(() {
                _isPremium = true;
                _isLoaded = false;
              });
              _bannerAd?.dispose();
              _bannerAd = null;
            }
          });
        },
        onAdLoaded: (ad) async {
          final isPremium = await AdmobService.instance.checkIsPremium();
          if (!mounted || isPremium || !identical(_bannerAd, ad)) {
            if (identical(_bannerAd, ad)) _bannerAd = null;
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted && identical(_bannerAd, ad)) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
          debugPrint('AdmobBannerWidget: Banner yüklenemedi: $error');
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    SubscriptionScreen.premiumStatusChanges.removeListener(_onPremiumStatusChanged);
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPremium ||
        !_isLoaded ||
        _bannerAd == null ||
        kIsWeb ||
        AdmobService.instance.isRunningInTest) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: widget.margin,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showBadge) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'REKLAM',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ],
      ),
    );
  }
}
