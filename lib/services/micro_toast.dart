import 'package:flutter/material.dart';

/// VidSave Premium Minimal Micro Toast (Bildirim/Toast Katmanı)
///
/// Ekranda kaba kutular tutmak yerine, işlem başladığında veya tamamlandığında
/// sadece 2 saniye süzülüp kaybolan şık, minimal turuncu/teal mikro bildirim katmanı.
class VidSaveMicroToast {
  VidSaveMicroToast._();

  static const Color brandOrange = Color(0xFFFF5436);
  static const Color brandTeal = Color(0xFF20B8C5);
  static const Color surfaceDark = Color(0xFF1E2630);

  /// Minimal mikro bildirim (Micro Toast) gösterir.
  static void show(
    BuildContext context, {
    required String message,
    bool isLoading = false,
    bool isSuccess = false,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Önceki açık bildirimleri anında temizle
    messenger.clearSnackBars();

    final accentColor = isSuccess ? brandTeal : brandOrange;
    final effectiveIcon =
        icon ??
        (isSuccess
            ? Icons.check_circle_rounded
            : (isLoading ? null : Icons.bolt_rounded));

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: accentColor.withValues(alpha: 0.4),
            width: 1.2,
          ),
        ),
        backgroundColor: surfaceDark,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              const SizedBox(width: 12),
            ] else if (effectiveIcon != null) ...[
              Icon(effectiveIcon, color: accentColor, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        action: action,
      ),
    );
  }
}

/// Global pratik yardımcı metot: showMicroToast
void showMicroToast(
  BuildContext context, {
  required String message,
  bool isLoading = false,
  bool isSuccess = false,
  IconData? icon,
  Duration duration = const Duration(seconds: 2),
  SnackBarAction? action,
}) {
  VidSaveMicroToast.show(
    context,
    message: message,
    isLoading: isLoading,
    isSuccess: isSuccess,
    icon: icon,
    duration: duration,
    action: action,
  );
}
