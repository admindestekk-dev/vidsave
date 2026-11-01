import 'package:flutter/services.dart';

class ExternalAppDownloadOverlayStatus {
  const ExternalAppDownloadOverlayStatus({
    required this.canDrawOverlays,
    required this.hasUsageAccess,
    required this.enabled,
  });

  final bool canDrawOverlays;
  final bool hasUsageAccess;
  final bool enabled;

  bool get hasRequiredPermissions => canDrawOverlays && hasUsageAccess;

  factory ExternalAppDownloadOverlayStatus.fromMap(
    Map<Object?, Object?> value,
  ) {
    return ExternalAppDownloadOverlayStatus(
      canDrawOverlays: value['canDrawOverlays'] == true,
      hasUsageAccess: value['hasUsageAccess'] == true,
      enabled: value['enabled'] == true,
    );
  }
}

class ExternalAppDownloadOverlay {
  ExternalAppDownloadOverlay._();

  static const MethodChannel _channel = MethodChannel(
    'vidsave/external_app_download_overlay',
  );

  static Future<ExternalAppDownloadOverlayStatus> getStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'getStatus',
    );
    if (result == null) {
      throw PlatformException(
        code: 'missing_status',
        message: 'Dış uygulama indirme durumu alınamadı.',
      );
    }
    return ExternalAppDownloadOverlayStatus.fromMap(result);
  }

  static Future<void> requestNextPermission() async {
    await _channel.invokeMethod<void>('requestNextPermission');
  }

  static Future<void> start() async {
    await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}
