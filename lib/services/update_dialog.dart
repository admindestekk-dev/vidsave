import 'dart:io';

import 'package:flutter/material.dart';

import 'app_update_service.dart';

/// VidSave Tasarım Dilinde Modern ve Kullanıcı Dostu Güncelleme İletişim Kutusu.
///
/// Zorunlu (force/mandatory) güncellemelerde kapatılamaz (`barrierDismissible: false`),
/// esnek (optional) güncellemelerde ise "Daha Sonra" seçeneği sunar.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.updateResult, this.onLater});

  final AppUpdateCheckResult updateResult;
  final VoidCallback? onLater;

  /// Kolayca güncelleme modalını açmak için statik yardımcı metot
  static Future<void> show(
    BuildContext context, {
    required AppUpdateCheckResult updateResult,
    VoidCallback? onLater,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: !updateResult.isMandatory,
      builder: (ctx) => PopScope(
        canPop: !updateResult.isMandatory,
        child: UpdateDialog(updateResult: updateResult, onLater: onLater),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _handleUpdate() async {
    final updateResult = widget.updateResult;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Google Play Store başlatılıyor…';
    });

    try {
      // 1. Eğer Google Play resmi In-App Update kullanılabilir durumdaysa
      if (Platform.isAndroid && updateResult.playStoreUpdateInfo != null) {
        final info = updateResult.playStoreUpdateInfo!;

        if (updateResult.isMandatory && info.immediateUpdateAllowed) {
          final res = await AppUpdateService.instance.triggerImmediateUpdate();
          if (res != null) {
            if (mounted) Navigator.of(context, rootNavigator: true).pop();
            return;
          }
        } else if (info.flexibleUpdateAllowed) {
          setState(() {
            _statusMessage = 'Güncelleme arka planda indiriliyor…';
          });
          await AppUpdateService.instance.triggerFlexibleUpdate(
            onDownloaded: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Güncelleme indirildi! Yüklemeyi tamamlamak için dokunun.',
                    ),
                    action: SnackBarAction(
                      label: 'YÜKLE',
                      onPressed: () {
                        AppUpdateService.instance.completeFlexibleUpdate();
                      },
                    ),
                    duration: const Duration(seconds: 15),
                  ),
                );
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
          );
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          return;
        }
      }

      // 2. Fallback: Google Play Store uygulamasını / linkini aç
      await AppUpdateService.instance.openPlayStore(
        customUrl: updateResult.storeUrl,
      );

      if (!updateResult.isMandatory && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (e) {
      debugPrint('UpdateDialog güncelleme hatası: $e');
      await AppUpdateService.instance.openPlayStore(
        customUrl: updateResult.storeUrl,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final res = widget.updateResult;
    final isMandatory = res.isMandatory;

    final primaryColor = const Color(0xFF00B4D8);
    final accentGradient = const LinearGradient(
      colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // İkon Rozeti
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: accentGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Başlık
            Text(
              isMandatory
                  ? 'Kritik Güncelleme Gerekli!'
                  : 'Yeni Sürüm Yayında! 🚀',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Sürüm Bilgisi Rozeti
            if (res.latestVersion != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Mevcut: v${res.currentVersion} ➔ Yeni: v${res.latestVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),

            // Açıklama / Güncelleme Notu
            Text(
              res.releaseNotes ??
                  (isMandatory
                      ? 'VidSave uygulamasının kesintisiz ve yüksek hızda çalışmaya devam edebilmesi için Play Store üzerinden güncellemeniz zorunludur.'
                      : 'Yeni video indirme motoru, hata düzeltmeleri ve performans iyileştirmeleri içeren yeni sürüm hazır.'),
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF475569),
              ),
              textAlign: TextAlign.center,
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF00B4D8),
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Güncelle Butonu
            ElevatedButton(
              onPressed: _isLoading ? null : _handleUpdate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.play_arrow_rounded, size: 22),
                        SizedBox(width: 6),
                        Text(
                          'Google Play\'de Güncelle',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),

            // İsteğe bağlı güncellemelerde "Daha Sonra" seçeneği
            if (!isMandatory) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        widget.onLater?.call();
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                child: Text(
                  'Daha Sonra',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF64748B)
                        : const Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
