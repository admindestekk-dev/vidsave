import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'admob_service.dart';

class AdmobTestScreen extends StatefulWidget {
  const AdmobTestScreen({super.key});

  @override
  State<AdmobTestScreen> createState() => _AdmobTestScreenState();
}

class _AdmobTestScreenState extends State<AdmobTestScreen> {
  BannerAd? _bannerAd;
  NativeAd? _nativeAd;
  InterstitialAd? _interstitialAd;
  AppOpenAd? _appOpenAd;
  String? _bannerError;
  String? _nativeError;
  String? _interstitialError;
  String? _appOpenError;
  bool _isInitializing = true;
  bool _isLoadingInterstitial = false;
  bool _isLoadingAppOpen = false;
  bool _isShowingFullScreenAd = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAndLoadAds();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _nativeAd?.dispose();
    _interstitialAd?.dispose();
    _appOpenAd?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoadAds() async {
    try {
      await AdmobService.instance.initialize();
      if (!mounted) return;
      if (!AdmobService.instance.isInitialized) {
        setState(() {
          _isInitializing = false;
          _bannerError = 'AdMob SDK başlatılamadı. Tekrar deneyin.';
          _nativeError = _bannerError;
          _interstitialError = _bannerError;
          _appOpenError = _bannerError;
        });
        return;
      }
      if (!AdmobService.instance.canRequestAds) {
        setState(() {
          _isInitializing = false;
          _bannerError =
              'Gizlilik izni alınmadığı için bu bölgede reklam isteği gönderilemiyor.';
        });
        return;
      }

      setState(() => _isInitializing = false);
      await Future.wait([
        _loadBanner(),
        _loadNative(),
        _loadInterstitial(),
        _loadAppOpen(),
      ]);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _bannerError = 'AdMob başlatılamadı: $error';
      });
    }
  }

  Future<void> _loadBanner() async {
    if (_bannerAd != null || _isInitializing) return;
    await AdmobService.instance.initialize();
    if (!AdmobService.instance.isInitialized) {
      if (mounted) {
        setState(() => _bannerError = 'AdMob SDK başlatılamadı.');
      }
      return;
    }
    if (!mounted) return;
    final ad = BannerAd(
      adUnitId: AdmobService.testAdUnitId('banner'),
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _bannerError = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerError = error.message);
        },
      ),
    );
    await ad.load();
  }

  Future<void> _loadNative() async {
    if (_nativeAd != null || _isInitializing) return;
    final theme = Theme.of(context);
    await AdmobService.instance.initialize();
    if (!AdmobService.instance.isInitialized) {
      if (mounted) {
        setState(() => _nativeError = 'AdMob SDK başlatılamadı.');
      }
      return;
    }
    if (!mounted) return;
    final ad = NativeAd(
      adUnitId: AdmobService.testAdUnitId('native'),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _nativeAd = ad as NativeAd;
            _nativeError = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _nativeError = error.message);
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: theme.colorScheme.surface,
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFFFF5436),
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: theme.colorScheme.onSurface,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: theme.colorScheme.onSurfaceVariant,
          size: 13,
        ),
      ),
    );
    await ad.load();
  }

  Future<void> _loadInterstitial() async {
    if (_interstitialAd != null || _isLoadingInterstitial || _isInitializing) {
      return;
    }
    await AdmobService.instance.initialize();
    if (!AdmobService.instance.isInitialized) {
      if (mounted) {
        setState(() => _interstitialError = 'AdMob SDK başlatılamadı.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingInterstitial = true;
      _interstitialError = null;
    });
    await InterstitialAd.load(
      adUnitId: AdmobService.testAdUnitId('interstitial'),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _interstitialAd = ad;
            _isLoadingInterstitial = false;
          });
        },
        onAdFailedToLoad: (error) {
          if (mounted) {
            setState(() {
              _interstitialError = error.message;
              _isLoadingInterstitial = false;
            });
          }
        },
      ),
    );
  }

  Future<void> _loadAppOpen() async {
    if (_appOpenAd != null || _isLoadingAppOpen || _isInitializing) return;
    await AdmobService.instance.initialize();
    if (!AdmobService.instance.isInitialized) {
      if (mounted) {
        setState(() => _appOpenError = 'AdMob SDK başlatılamadı.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingAppOpen = true;
      _appOpenError = null;
    });
    await AppOpenAd.load(
      adUnitId: AdmobService.testAdUnitId('appOpen'),
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _appOpenAd = ad;
            _isLoadingAppOpen = false;
          });
        },
        onAdFailedToLoad: (error) {
          if (mounted) {
            setState(() {
              _appOpenError = error.message;
              _isLoadingAppOpen = false;
            });
          }
        },
      ),
    );
  }

  Future<void> _showInterstitial() async {
    final ad = _interstitialAd;
    if (ad == null || _isShowingFullScreenAd) return;
    setState(() {
      _interstitialAd = null;
      _isShowingFullScreenAd = true;
    });
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (mounted) setState(() => _isShowingFullScreenAd = false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (mounted) {
          setState(() {
            _interstitialError = error.message;
            _isShowingFullScreenAd = false;
          });
        }
      },
    );
    await ad.show();
  }

  Future<void> _showAppOpen() async {
    final ad = _appOpenAd;
    if (ad == null || _isShowingFullScreenAd) return;
    setState(() {
      _appOpenAd = null;
      _isShowingFullScreenAd = true;
    });
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (mounted) setState(() => _isShowingFullScreenAd = false);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (mounted) {
          setState(() {
            _appOpenError = error.message;
            _isShowingFullScreenAd = false;
          });
        }
      },
    );
    await ad.show();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return Scaffold(
        appBar: AppBar(title: const Text('AdMob test reklamları')),
        body: const Center(
          child: Text('AdMob mobil reklamları Android ve iOS’ta test edilir.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('AdMob test reklamları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu alan Google’ın resmi test reklam birimlerini kullanır. '
                      'Sayfa açılırken banner, yerel, geçiş ve açılış reklamları '
                      'yüklenir; tam ekran reklamlar yalnızca test düğmesine '
                      'dokununca gösterilir. EEA/ABD izin ekranını test etmek '
                      'için VIDSAVE_UMP_TEST_DEVICE_ID ve '
                      'VIDSAVE_UMP_DEBUG_GEOGRAPHY derleme ayarlarını kullanın.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AdTestCard(
            title: 'Banner reklam',
            description:
                _bannerError ??
                (_bannerAd == null
                    ? 'Sayfa içinde sabit boyutlu test reklamı.'
                    : 'Test banner reklamı yüklendi.'),
            onPressed: _bannerAd == null ? _loadBanner : null,
            buttonLabel: _isInitializing
                ? 'SDK hazırlanıyor…'
                : _bannerAd == null
                ? 'Banner yükle'
                : 'Yüklendi',
          ),
          if (_bannerAd != null) ...[
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _AdTestCard(
            title: 'Geçiş reklamı',
            description:
                _interstitialError ??
                (_interstitialAd != null
                    ? 'Tam ekran test reklamı hazır.'
                    : _isLoadingInterstitial
                    ? 'Reklam yükleniyor…'
                    : 'Yalnızca aşağıdaki düğmeye dokununca açılır.'),
            onPressed: _interstitialAd != null
                ? _showInterstitial
                : _isLoadingInterstitial || _isInitializing
                ? null
                : _loadInterstitial,
            buttonLabel: _interstitialAd != null
                ? 'Test reklamını göster'
                : _isLoadingInterstitial || _isInitializing
                ? 'Yükleniyor…'
                : 'Geçiş reklamı yükle',
          ),
          const SizedBox(height: 12),
          _AdTestCard(
            title: 'Uygulama açılış reklamı',
            description:
                _appOpenError ??
                (_appOpenAd != null
                    ? 'Tam ekran test reklamı hazır.'
                    : _isLoadingAppOpen
                    ? 'Reklam yükleniyor…'
                    : 'Uygulama açılışında otomatik gösterilmez; '
                          'yalnızca test düğmesiyle açılır.'),
            onPressed: _appOpenAd != null
                ? _showAppOpen
                : _isLoadingAppOpen || _isInitializing
                ? null
                : _loadAppOpen,
            buttonLabel: _appOpenAd != null
                ? 'Test reklamını göster'
                : _isLoadingAppOpen || _isInitializing
                ? 'Yükleniyor…'
                : 'Açılış reklamını yükle',
          ),
          const SizedBox(height: 12),
          _AdTestCard(
            title: 'Yerel reklam',
            description:
                _nativeError ??
                (_nativeAd == null
                    ? 'Uygulama tasarımına uyumlu test reklamı.'
                    : 'Test yerel reklamı yüklendi.'),
            onPressed: _nativeAd == null && !_isInitializing
                ? _loadNative
                : null,
            buttonLabel: _isInitializing
                ? 'SDK hazırlanıyor…'
                : _nativeAd == null
                ? 'Yerel reklam yükle'
                : 'Yüklendi',
          ),
          if (_nativeAd != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 320,
                minHeight: 320,
                maxHeight: 400,
              ),
              child: AdWidget(ad: _nativeAd!),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdTestCard extends StatelessWidget {
  const _AdTestCard({
    required this.title,
    required this.description,
    required this.onPressed,
    required this.buttonLabel,
  });

  final String title;
  final String description;
  final VoidCallback? onPressed;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description),
            const SizedBox(height: 12),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
