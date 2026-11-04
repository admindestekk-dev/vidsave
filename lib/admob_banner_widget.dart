import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';

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

    _loadBannerAd();
  }

  void _loadBannerAd() {
    _bannerAd?.dispose();
    final ad = BannerAd(
      adUnitId: AdmobService.testAdUnitId('banner'),
      size: widget.adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
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
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
          debugPrint('AdmobBannerWidget: Banner yüklenemedi: $error');
        },
      ),
    );

    ad.load();
  }

  @override
  void dispose() {
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
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
