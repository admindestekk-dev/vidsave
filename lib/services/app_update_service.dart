import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../remote_config_service.dart';

/// Güncelleme kontrolü neticesinde dönen detaylı model
class AppUpdateCheckResult {
  final bool hasUpdate;
  final bool isMandatory;
  final String currentVersion;
  final int currentBuildNumber;
  final String? latestVersion;
  final int? latestBuildNumber;
  final String? releaseNotes;
  final String storeUrl;
  final AppUpdateInfo? playStoreUpdateInfo;

  const AppUpdateCheckResult({
    required this.hasUpdate,
    required this.isMandatory,
    required this.currentVersion,
    required this.currentBuildNumber,
    this.latestVersion,
    this.latestBuildNumber,
    this.releaseNotes,
    required this.storeUrl,
    this.playStoreUpdateInfo,
  });
}

/// Google Play Store ve Firebase Tabanlı Akıllı Güncelleme Servisi.
///
/// Sağladığı Yetenekler:
/// 1. Resmi Google Play Core In-App Update API (`in_app_update`):
///    - Anında tam ekran güncelleme (`performImmediateUpdate`)
///    - Arka planda esnek indirme (`startFlexibleUpdate` & `completeFlexibleUpdate`)
/// 2. Firebase Remote Config Kontrolü:
///    - `latest_version`, `min_required_version`, `force_update`, `update_notes`, `play_store_url`
///    - Play Store In-App API mağaza dışı testlerde veya gecikmelerde devreye girerek
///      kullanıcıya kesintisiz güncelleme bildirimi ve linki sunar.
/// 3. Doğrudan Google Play Store uygulamasını / web sayfasını açma (`openPlayStore`)
class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  PackageInfo? _cachedPackageInfo;
  bool _isChecking = false;

  /// Varsayılan paket ve Play Store URL
  static const String defaultPackageName = 'dev.admindestekk.vidsave';
  static const String defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=$defaultPackageName';

  /// Cihazdaki uygulamanın paket bilgilerini döner
  Future<PackageInfo> getPackageInfo() async {
    if (_cachedPackageInfo != null) return _cachedPackageInfo!;
    try {
      _cachedPackageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      _cachedPackageInfo = PackageInfo(
        appName: 'VidSave',
        packageName: defaultPackageName,
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    }
    return _cachedPackageInfo!;
  }

  /// Aktif Play Store URL'i (Remote Config veya fallback)
  String get playStoreUrl {
    final remoteUrl = RemoteConfigService.instance.playStoreUrl;
    if (remoteUrl.trim().isNotEmpty) return remoteUrl.trim();
    final pkg = _cachedPackageInfo?.packageName ?? defaultPackageName;
    return 'https://play.google.com/store/apps/details?id=$pkg';
  }

  /// Google Play Store sayfasını yerel uygulama olarak açar (market:// -> https:// fallback)
  Future<bool> openPlayStore({String? customUrl}) async {
    final targetUrl = customUrl ?? playStoreUrl;
    final pkg = _cachedPackageInfo?.packageName ?? defaultPackageName;

    // 1. Önce native market:// URI şemasını dene (Google Play uygulamasını doğrudan açar)
    if (Platform.isAndroid) {
      final marketUri = Uri.parse('market://details?id=$pkg');
      try {
        if (await canLaunchUrl(marketUri)) {
          final launched = await launchUrl(
            marketUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return true;
        }
      } catch (e) {
        debugPrint(
          'AppUpdateService: market:// açılamadı, web fallback deneniyor: $e',
        );
      }
    }

    // 2. Web fallback (https://play.google.com/...)
    try {
      final webUri = Uri.parse(targetUrl);
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateService: Play Store açılamadı: $e');
      return false;
    }
  }

  /// Güncelleme kontrolü yapar (Resmi Play Core API + Firebase Remote Config sentezi)
  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (_isChecking) {
      final pkg = await getPackageInfo();
      return AppUpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentVersion: pkg.version,
        currentBuildNumber: int.tryParse(pkg.buildNumber) ?? 1,
        storeUrl: playStoreUrl,
      );
    }
    _isChecking = true;

    try {
      final pkg = await getPackageInfo();
      final currentBuild = int.tryParse(pkg.buildNumber) ?? 1;
      final currentVer = pkg.version;

      AppUpdateInfo? playUpdateInfo;

      // 1. Resmi Google Play In-App Update API Kontrolü (Sadece Android ve Play Store kurulumlarında)
      if (Platform.isAndroid && !kIsWeb) {
        try {
          playUpdateInfo = await InAppUpdate.checkForUpdate();
          debugPrint(
            'AppUpdateService [Play Store API]: UpdateAvailability: ${playUpdateInfo.updateAvailability}, '
            'ImmediateAllowed: ${playUpdateInfo.immediateUpdateAllowed}, '
            'FlexibleAllowed: ${playUpdateInfo.flexibleUpdateAllowed}, '
            'AvailableVersionCode: ${playUpdateInfo.availableVersionCode}',
          );

          if (playUpdateInfo.updateAvailability ==
              UpdateAvailability.updateAvailable) {
            final isMandatory =
                playUpdateInfo.immediateUpdateAllowed &&
                (RemoteConfigService.instance.isForceUpdateEnabled ||
                    (playUpdateInfo.updatePriority >= 4));

            return AppUpdateCheckResult(
              hasUpdate: true,
              isMandatory: isMandatory,
              currentVersion: currentVer,
              currentBuildNumber: currentBuild,
              latestBuildNumber: playUpdateInfo.availableVersionCode,
              storeUrl: playStoreUrl,
              playStoreUpdateInfo: playUpdateInfo,
            );
          }
        } catch (playErr) {
          debugPrint(
            'AppUpdateService: Play Store API yerel/test hatası (Remote Config fallback kullanılacak): $playErr',
          );
        }
      }

      // 2. Firebase Remote Config Kontrolü
      final remoteConfig = RemoteConfigService.instance;
      final latestVer = remoteConfig.latestAppVersion;
      final minRequiredVer = remoteConfig.minRequiredVersion;
      final remoteForce = remoteConfig.isForceUpdateEnabled;
      final releaseNotes = remoteConfig.updateReleaseNotes;

      bool updateRequired = false;
      bool mandatory = remoteForce;

      if (latestVer.isNotEmpty && _compareVersions(latestVer, currentVer) > 0) {
        updateRequired = true;
      }

      if (minRequiredVer.isNotEmpty &&
          _compareVersions(minRequiredVer, currentVer) > 0) {
        updateRequired = true;
        mandatory = true;
      }

      return AppUpdateCheckResult(
        hasUpdate: updateRequired,
        isMandatory: mandatory,
        currentVersion: currentVer,
        currentBuildNumber: currentBuild,
        latestVersion: latestVer.isNotEmpty ? latestVer : null,
        releaseNotes: releaseNotes.isNotEmpty ? releaseNotes : null,
        storeUrl: playStoreUrl,
        playStoreUpdateInfo: playUpdateInfo,
      );
    } catch (e, st) {
      debugPrint('AppUpdateService checkForUpdate hatası: $e\n$st');
      final pkg = await getPackageInfo();
      return AppUpdateCheckResult(
        hasUpdate: false,
        isMandatory: false,
        currentVersion: pkg.version,
        currentBuildNumber: int.tryParse(pkg.buildNumber) ?? 1,
        storeUrl: playStoreUrl,
      );
    } finally {
      _isChecking = false;
    }
  }

  /// Resmi Google Play Tam Ekran Zorunlu Güncellemesini Başlatır
  Future<AppUpdateResult?> triggerImmediateUpdate() async {
    if (!Platform.isAndroid || kIsWeb) return null;
    try {
      return await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      debugPrint('AppUpdateService performImmediateUpdate hatası: $e');
      // Play API başarısız olursa doğrudan Play Store sayfasını aç
      await openPlayStore();
      return null;
    }
  }

  /// Resmi Google Play Esnek (Arka Planda İndirme) Güncellemesini Başlatır
  Future<AppUpdateResult?> triggerFlexibleUpdate({
    VoidCallback? onDownloaded,
  }) async {
    if (!Platform.isAndroid || kIsWeb) return null;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        onDownloaded?.call();
      }
      return result;
    } catch (e) {
      debugPrint('AppUpdateService startFlexibleUpdate hatası: $e');
      await openPlayStore();
      return null;
    }
  }

  /// Esnek güncelleme tamamlandığında kurulumu bitirip uygulamayı yeniden başlatır
  Future<void> completeFlexibleUpdate() async {
    if (!Platform.isAndroid || kIsWeb) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('AppUpdateService completeFlexibleUpdate hatası: $e');
    }
  }

  /// Sürüm numarası kıyaslayıcı (Örn: "1.0.2" vs "1.0.0" -> 1, "1.0.0" vs "1.0.0" -> 0)
  int _compareVersions(String v1, String v2) {
    try {
      final cleanV1 = v1.split('+').first.trim();
      final cleanV2 = v2.split('+').first.trim();

      final parts1 = cleanV1
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      final parts2 = cleanV2
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();

      final maxLen = parts1.length > parts2.length
          ? parts1.length
          : parts2.length;
      while (parts1.length < maxLen) {
        parts1.add(0);
      }
      while (parts2.length < maxLen) {
        parts2.add(0);
      }

      for (var i = 0; i < maxLen; i++) {
        if (parts1[i] > parts2[i]) return 1;
        if (parts1[i] < parts2[i]) return -1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
