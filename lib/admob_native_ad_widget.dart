import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';

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

  @override
  void initState() {
    super.initState();
    _checkPremiumAndLoad();
  }

  Future<void> _checkPremiumAndLoad() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (AdmobService.instance.isRunningInTest) return;

    final isPrem = await AdmobService.instance.checkIsPremium();
    if (!mounted) return;
    if (isPrem) {
      setState(() => _isPremium = true);
      return;
    }

    await AdmobService.instance.initialize();
    if (!mounted) return;
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
        onAdLoaded: (ad) {
          if (!mounted) {
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
          if (mounted) {
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

    ad.load();
  }

  @override
  void dispose() {
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
