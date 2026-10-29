import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'media_downloader.dart';
import 'services/api_service.dart';

/// Geleceğe Hazır Evrensel Hata Yakalama ve Güvenlik Kalkanı
///
/// DioException, FormatException, TypeError veya MediaResolverException gibi
/// tüm hata türlerini katı try-catch sarmalı ile güvenli, kullanıcı dostu
/// ve çok dilli (i18n) mesajlara dönüştürür.
class DownloadExceptionHandler {
  DownloadExceptionHandler._();

  /// Hata nesnesini kullanıcının yerel diline (AppLocalizations) göre
  /// şık ve anlaşılır bir hata metnine dönüştürür.
  static String getFriendlyMessage(Object? error, BuildContext? context) {
    AppLocalizations? l10n;
    if (context != null && context.mounted) {
      try {
        l10n = AppLocalizations.of(context);
      } catch (_) {}
    }

    if (error == null) {
      return l10n?.text('err_download_failed') ??
          'İndirme tamamlanamadı. Lütfen tekrar deneyin.';
    }

    // 1. Zaten özelleştirilmiş çözücü ve indirme istisnaları
    if (error is ApiException) {
      return error.message;
    }
    if (error is MediaVerificationException) {
      return error.message;
    }
    if (error is MediaResolverException) {
      return error.message;
    }
    if (error is MediaDownloadException) {
      return error.message;
    }

    // 2. Dio Ağ ve Protokol İstisnaları
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return l10n?.text('err_connection_timeout') ??
              'Bağlantı zaman aşımına uğradı. Ağ bağlantınızı kontrol edin.';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == 403) {
            return l10n?.text('err_access_denied') ??
                'Erişim reddedildi veya içerik korumalı (403 Forbidden).';
          }
          if (statusCode == 404) {
            return l10n?.text('err_not_found') ??
                'Medya veya sayfa bulunamadı (404 Not Found).';
          }
          if (statusCode != null && statusCode >= 500) {
            return l10n?.text('err_server') ??
                'Medya sunucusunda geçici bir hata oluştu ($statusCode).';
          }
          return 'Sunucudan geçersiz yanıt alındı (HTTP $statusCode).';
        case DioExceptionType.connectionError:
          return l10n?.text('err_connection') ??
              'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.';
        case DioExceptionType.cancel:
          return 'İndirme işlemi iptal edildi.';
        default:
          return 'Ağ isteği sırasında bir hata oluştu.';
      }
    }

    // 3. Veri Biçimlendirme ve Tip Hataları
    if (error is FormatException) {
      return l10n?.text('err_format') ??
          'Medya adresi veya sayfa verisi ayrıştırılamadı.';
    }

    if (error is TypeError) {
      return 'Medya verisi beklenmedik bir formatta geldi.';
    }

    if (error is SocketException) {
      return l10n?.text('err_connection') ??
          'İnternet bağlantınızı kontrol edin.';
    }

    if (error is TimeoutException) {
      return l10n?.text('err_connection_timeout') ??
          'İşlem zaman aşımına uğradı. Lütfen tekrar deneyin.';
    }

    // 4. Genel Geri Dönüş
    final errStr = error.toString();
    if (errStr.contains('ApiException:') ||
        errStr.contains('MediaVerificationException:') ||
        errStr.contains('MediaResolverException:') ||
        errStr.contains('MediaDownloadException:')) {
      return errStr.replaceFirst(RegExp(r'^.*?Exception:\s*'), '');
    }

    if (errStr.startsWith('Exception:')) {
      final unwrapped = errStr.replaceFirst('Exception:', '').trim();
      if (unwrapped.isNotEmpty) return unwrapped;
    }

    return l10n?.text('err_download_failed') ??
        'İndirme tamamlanamadı. Lütfen bağlantıyı kontrol edin.';
  }

  /// Herhangi bir bilinmeyen hatayı kontrollü bir MediaResolverException'a dönüştürür
  static MediaResolverException mapToResolverException(Object? error, Uri uri) {
    if (error is MediaResolverException) return error;
    final friendly = getFriendlyMessage(error, null);
    return MediaResolverException(friendly);
  }

  /// Hata durumunda dialog kutusunu kapatmadan, kullanıcı diline uygun şık bir SnackBar gösterir
  static void showErrorSnackBar(BuildContext context, Object? error) {
    if (!context.mounted) return;
    final message = getFriendlyMessage(error, context);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
