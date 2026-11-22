import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';
import 'services/ad_shield_service.dart';
import 'subscription_screen.dart';

/// AdMob ve Google Play politikalarına tam uyumlu Yerel (Native) Reklam Bileşeni.
///
/// Uygulama tasarım diliyle bütünleşik modern kart yapısı sunar.
class AdmobNativeAdWidget extends StatefulWidget {
  const AdmobNativeAdWidget({
    super.key,
    this.templateType = TemplateType.small,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final TemplateType templateType;
  final EdgeInsetsGeometry margin;

  @override
  State<AdmobNativeAdWidget> createState() => _AdmobNativeAdWidgetState();
}

class _AdmobNativeAdWidgetState extends State<AdmobNativeAdWidget> {
  NativeAd? _nativeAd;
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
      _nativeAd?.dispose();
      _nativeAd = null;
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
      _nativeAd?.dispose();
      _nativeAd = null;
      return;
    }
    if (_isPremium) setState(() => _isPremium = false);
    if (_nativeAd != null) return;

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

    _loadNativeAd();
  }

  void _loadNativeAd() {
    _nativeAd?.dispose();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ad = NativeAd(
      adUnitId: AdmobService.nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdClicked: (ad) {
          debugPrint('AdmobNativeAdWidget: Native tıklandı, AdShieldService kaydı alınıyor.');
          AdShieldService.instance.registerAdClick().then((newlyBlocked) {
            if (newlyBlocked && mounted) {
              setState(() {
                _isPremium = true;
                _isLoaded = false;
              });
              _nativeAd?.dispose();
              _nativeAd = null;
            }
          });
        },
        onAdLoaded: (ad) async {
          final isPremium = await AdmobService.instance.checkIsPremium();
          if (!mounted || isPremium || !identical(_nativeAd, ad)) {
            if (identical(_nativeAd, ad)) _nativeAd = null;
            ad.dispose();
            return;
          }
          setState(() {
            _nativeAd = ad as NativeAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted && identical(_nativeAd, ad)) {
            setState(() {
              _nativeAd = null;
              _isLoaded = false;
            });
          }
          debugPrint('AdmobNativeAdWidget: Native yüklenemedi: $error');
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.templateType,
        mainBackgroundColor: isDark ? const Color(0xFF1E2630) : Colors.white,
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFFFF5436),
          size: 13,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.white : const Color(0xFF172B3A),
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: isDark ? Colors.white60 : const Color(0xFF87949D),
          size: 12,
        ),
      ),
    );

    _nativeAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    SubscriptionScreen.premiumStatusChanges.removeListener(_onPremiumStatusChanged);
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPremium ||
        !_isLoaded ||
        _nativeAd == null ||
        kIsWeb ||
        AdmobService.instance.isRunningInTest) {
      return const SizedBox.shrink();
    }

    final height = widget.templateType == TemplateType.small ? 90.0 : 320.0;

    return Container(
      margin: widget.margin,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white12
              : const Color(0xFFE5E9EB),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
