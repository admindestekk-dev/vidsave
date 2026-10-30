import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_dio.dart';

/// Varsayılan canlı sunucu adresi (Render Pro 7/24 Kesintisiz Canlı API).
/// Port numarası içermeyen doğrudan standart ve şifreli HTTPS adresi.
const String kDefaultServerBaseUrl = 'https://vidsave-q7ut.onrender.com';

/// Sunucu tabanlı medya analiz sonucunu temsil eden veri modeli.
class AnalyzeResult {
  final String downloadUrl;
  final String title;
  final String filename;
  final String? thumbnail;
  final int? duration;
  final String type; // 'video' veya 'mp3'
  final String ext;
  final Map<String, String>? headers;

  const AnalyzeResult({
    required this.downloadUrl,
    required this.title,
    required this.filename,
    this.thumbnail,
    this.duration,
    required this.type,
    required this.ext,
    this.headers,
  });

  factory AnalyzeResult.fromJson(Map<String, dynamic> json) {
    final rawUrl =
        json['download_url']?.toString() ?? json['url']?.toString() ?? '';
    if (rawUrl.isEmpty) {
      throw const FormatException(
        'Sunucudan geçerli bir download_url gelmedi.',
      );
    }

    final rawTitle = json['title']?.toString() ?? 'vidsave_media';
    final rawType = json['type']?.toString().toLowerCase() ?? 'video';
    final rawExt =
        json['ext']?.toString().toLowerCase() ??
        (rawType == 'mp3' ? 'mp3' : 'mp4');
    final rawFilename = json['filename']?.toString() ?? '$rawTitle.$rawExt';

    Map<String, String>? extraHeaders;
    if (json['headers'] is Map) {
      extraHeaders = (json['headers'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    int? parsedDuration;
    if (json['duration'] != null) {
      if (json['duration'] is num) {
        parsedDuration = (json['duration'] as num).toInt();
      } else {
        parsedDuration = int.tryParse(json['duration'].toString());
      }
    }

    return AnalyzeResult(
      downloadUrl: rawUrl,
      title: rawTitle,
      filename: rawFilename,
      thumbnail: json['thumbnail']?.toString(),
      duration: parsedDuration,
      type: rawType,
      ext: rawExt,
      headers: extraHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
    'download_url': downloadUrl,
    'title': title,
    'filename': filename,
    'thumbnail': thumbnail,
    'duration': duration,
    'type': type,
    'ext': ext,
    'headers': headers,
  };
}

/// Sunucu isteklerinde karşılaşılan özel hata istisnası.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}

/// VidSave Backend ile iletişim kuran kurumsal ve kararlı ağ servis sınıfı.
///
/// Render Pro altyapısındaki `/api/analyze` uç noktasına istek atarak
/// YouTube, TikTok, Facebook, Vimeo ve diğer platformların şifrelerini sunucuda
/// çözer ve doğrudan indirilebilir temiz bir [AnalyzeResult] döndürür.
class ApiService {
  /// Eski port numaralarını (:8787, :10000 vb.) ve yerel adres kalıntılarını
  /// temizleyerek güvenli HTTPS tabanlı Render Pro API adresine normalize eder.
  static String cleanBaseUrl(String? url) {
    final candidate = (url ?? '').trim();
    if (candidate.isEmpty || candidate.contains('SUNUCU_IP_ADRESINIZ')) {
      return kDefaultServerBaseUrl;
    }
    // Eski portlu (:8787, :10000 vb.) ekleri temizle
    var sanitized = candidate.replaceAll(RegExp(r':(8787|10000)\b'), '');
    // Render API adresi şifreli ve güvenli HTTPS protokolü ile çalışır
    if (sanitized.startsWith('http://') && sanitized.contains('onrender.com')) {
      sanitized = sanitized.replaceFirst('http://', 'https://');
    }
    return sanitized.replaceAll(RegExp(r'/+$'), '');
  }

  ApiService({String? baseUrl, Dio? dioClient})
    : _baseUrl = cleanBaseUrl(baseUrl),
      _dio =
          dioClient ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              headers: const {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent': 'VidSave-App/1.0 (Android/iOS; Flutter)',
              },
            ),
          ) {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
  }

  static ApiService? _instance;

  /// Global erişilebilir tekil örnek
  static ApiService get instance => _instance ??= ApiService();

  /// Özel bir ApiService örneği atamak için kullanılır (örneğin birim testlerde).
  static void setInstance(ApiService service) {
    _instance = service;
  }

  String _baseUrl;
  final Dio _dio;

  String get baseUrl => _baseUrl;
  Dio get dio => _dio;

  /// Sunucu URL'sini çalışma zamanında dinamik olarak günceller
  void setBaseUrl(String newBaseUrl) {
    _baseUrl = cleanBaseUrl(newBaseUrl);
  }

  /// Verilen ham linki ve indirme tipini Python sunucusuna gönderir ve
  /// temiz [download_url] adresini içeren sonucu döndürür.
  ///
  /// [url]: Kullanıcının yapıştırdığı video/ses bağlantısı.
  /// [type]: 'video' veya 'mp3' (varsayılan: 'video').
  Future<AnalyzeResult> analyze({
    required String url,
    String type = 'video',
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      throw const ApiException('Lütfen geçerli bir bağlantı adresi girin.');
    }

    final targetEndpoint = '$_baseUrl/api/analyze';

    try {
      final response = await _dio.post<dynamic>(
        targetEndpoint,
        data: {
          'url': cleanUrl,
          'type': type.toLowerCase() == 'mp3' ? 'mp3' : 'video',
        },
        options: Options(
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data;
      if (data is! Map) {
        throw ApiException(
          'Sunucudan geçersiz veri biçimi alındı (JSON bekleniyordu).',
          statusCode: response.statusCode,
        );
      }

      final map = Map<String, dynamic>.from(data);
      if (response.statusCode != 200 || map['status'] == 'error') {
        final errObj = map['error'];
        String msg = 'Medya çözümlenemedi.';
        if (errObj is Map && errObj['message'] != null) {
          msg = errObj['message'].toString();
        } else if (map['message'] != null) {
          msg = map['message'].toString();
        }
        throw ApiException(msg, statusCode: response.statusCode);
      }

      return AnalyzeResult.fromJson(map);
    } on DioException catch (dioErr) {
      debugPrint(
        'ApiService DioException: ${dioErr.type} -> ${dioErr.message}',
      );
      String friendlyMessage = 'Sunucuya bağlanılamadı.';

      switch (dioErr.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          friendlyMessage = 'Sunucu yanıt verme süresi aşıldı (30s). Lütfen internet bağlantınızı kontrol edin.';
          break;
        case DioExceptionType.connectionError:
          friendlyMessage =
              'Sunucuya ulaşılamıyor ($_baseUrl). Sunucunun açık ve erişilebilir olduğundan emin olun.';
          break;
        case DioExceptionType.badResponse:
          final code = dioErr.response?.statusCode;
          friendlyMessage = 'Sunucu hata kodu döndürdü ($code).';
          break;
        case DioExceptionType.cancel:
          friendlyMessage = 'İstek iptal edildi.';
          break;
        default:
          friendlyMessage = 'Ağ hatası: ${dioErr.message}';
          break;
      }
      throw ApiException(
        friendlyMessage,
        statusCode: dioErr.response?.statusCode,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Beklenmeyen bir hata oluştu: $e');
    }
  }

  /// TikTok, Instagram, YouTube, Facebook, Twitter, Vimeo ve Dailymotion gibi
  /// tüm platformların güvenlik duvarlarını (Cloudflare, Akamai, Google, Meta)
  /// ve 403 Forbidden bot koruma mekanizmalarını aşmak için yasal tarayıcı
  /// kimliklerini (User-Agent, Referer, Origin, Sec-Fetch, Sec-Ch-Ua) kalıcı olarak mühürler.
  static Map<String, String> buildAggressiveBrowserHeaders({
    required Uri uri,
    Map<String, String>? extraHeaders,
  }) {
    final host = uri.host.toLowerCase();

    // 1. Masaüstü Chrome 124 Yasal Tarayıcı Kimlik Başlıkları
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'video/webm,video/mp4,video/*,audio/*,*/*;q=0.9',
      'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      // Sıkıştırmayı kapatıp ham veriyi pürüzsüz akıtır, erken bağlantı kopmasını engeller
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
      'Sec-Ch-Ua':
          '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
      'Sec-Fetch-Dest': 'video',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
    };

    // 2. Dinamik Platform Sahtelemesi (Platform-aware Referer ve Origin)
    if (host.contains('youtube.com') ||
        host.contains('googlevideo.com') ||
        host.contains('youtu.be')) {
      headers['Referer'] = 'https://www.youtube.com/';
      headers['Origin'] = 'https://www.youtube.com';
    } else if (host.contains('tiktok.com') ||
        host.contains('tiktokcdn.com') ||
        host.contains('byteoversea.com') ||
        host.contains('ibytedtos.com') ||
        host.contains('musical.ly')) {
      headers['Referer'] = 'https://www.tiktok.com/';
      headers['Origin'] = 'https://www.tiktok.com';
    } else if (host.contains('instagram.com') ||
        host.contains('cdninstagram.com') ||
        host.contains('fbcdn.net')) {
      headers['Referer'] = 'https://www.instagram.com/';
      headers['Origin'] = 'https://www.instagram.com';
    } else if (host.contains('facebook.com') ||
        host.contains('fb.watch') ||
        host.contains('facebook.net')) {
      headers['Referer'] = 'https://www.facebook.com/';
      headers['Origin'] = 'https://www.facebook.com';
    } else if (host.contains('pinterest.com') || host.contains('pinimg.com')) {
      headers['Referer'] = 'https://www.pinterest.com/';
      headers['Origin'] = 'https://www.pinterest.com';
    } else if (host.contains('twitter.com') ||
        host.contains('x.com') ||
        host.contains('twimg.com')) {
      headers['Referer'] = 'https://twitter.com/';
      headers['Origin'] = 'https://twitter.com';
    } else if (host.contains('vimeo.com') || host.contains('vimeocdn.com')) {
      headers['Referer'] = 'https://vimeo.com/';
      headers['Origin'] = 'https://vimeo.com';
    } else if (host.contains('dailymotion.com') || host.contains('dmcdn.net')) {
      headers['Referer'] = 'https://www.dailymotion.com/';
      headers['Origin'] = 'https://www.dailymotion.com';
    } else {
      headers['Referer'] = '${uri.scheme}://${uri.host}/';
      headers['Origin'] = '${uri.scheme}://${uri.host}';
    }

    // 3. Çerez havuzundaki geçerli çerezleri enjekte et
    try {
      final cookie = AppDio.cookieJar.getCookieHeader(uri);
      if (cookie != null && cookie.isNotEmpty) {
        headers['Cookie'] = cookie;
      }
    } catch (_) {}

    // 4. Sunucudan veya üst katmandan gelen özel başlıklar (varsa üzerine yazılır)
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      headers.addAll(extraHeaders);
    }

    // 5. Kesinlikle Content-Type: application/json gönderilmemelidir (GET video indirme isteklerinde 403 tetikler)
    headers.remove('Content-Type');

    return headers;
  }

  /// Sunucudan veya CDN'den gelen [downloadUrl] adresindeki dosyayı
  /// doğrudan cihaz hafızasına indirir ve canlı ilerleme yüzdesini bildirir.
  ///
  /// Tüm sosyal medya platformlarının bot koruma duvarlarını (Cloudflare, Akamai,
  /// TikTok, Instagram, YouTube, Facebook CDN) delecek agresif yasal tarayıcı
  /// başlıkları kalıcı olarak mühürlenmiştir.
  Future<File> downloadFile({
    required String downloadUrl,
    required String savePath,
    Map<String, String>? headers,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    // Relative URL geldiyse (örn. /download?job=xyz) baseUrl ile birleştir
    String effectiveUrl = downloadUrl.trim();
    if (!effectiveUrl.startsWith('http://') &&
        !effectiveUrl.startsWith('https://')) {
      final leadingSlash = effectiveUrl.startsWith('/') ? '' : '/';
      effectiveUrl = '$_baseUrl$leadingSlash$effectiveUrl';
    }

    final targetFile = File(savePath);
    final parentDir = targetFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final uri = Uri.tryParse(effectiveUrl) ?? Uri.parse(downloadUrl);
    final aggressiveHeaders = buildAggressiveBrowserHeaders(
      uri: uri,
      extraHeaders: headers,
    );

    // 403 engellerini bertaraf etmek için AppDio (CookieJar ve Maskeleme destekli) istemcisi kullanılır
    final downloadClient = AppDio.createClient();

    try {
      await downloadClient.download(
        effectiveUrl,
        savePath,
        options: Options(
          headers: aggressiveHeaders,
          followRedirects: true,
          maxRedirects: 10,
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(seconds: 30),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
        deleteOnError: true,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );

      return targetFile;
    } on DioException catch (dioErr) {
      // 403 Forbidden durumunda alternatif mobil tarayıcı kimliği (Android Chrome / no-cors) ile otomatik tekrar dene
      if (dioErr.response?.statusCode == 403) {
        debugPrint(
          'ApiService.downloadFile 403 Forbidden ile karşılaştı. Alternatif mobil tarayıcı kimliği ile tekrar deneniyor...',
        );
        try {
          final mobileHeaders = Map<String, String>.from(aggressiveHeaders);
          mobileHeaders['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
          mobileHeaders['Sec-Ch-Ua-Mobile'] = '?1';
          mobileHeaders['Sec-Ch-Ua-Platform'] = '"Android"';
          mobileHeaders['Sec-Fetch-Mode'] = 'no-cors';
          mobileHeaders['Accept-Encoding'] = 'identity';
          mobileHeaders['Connection'] = 'keep-alive';

          await downloadClient.download(
            effectiveUrl,
            savePath,
            options: Options(
              headers: mobileHeaders,
              followRedirects: true,
              maxRedirects: 10,
              receiveTimeout: const Duration(minutes: 30),
              sendTimeout: const Duration(seconds: 30),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ),
            deleteOnError: true,
            onReceiveProgress: onProgress,
            cancelToken: cancelToken,
          );

          return targetFile;
        } catch (retryErr) {
          debugPrint(
            'ApiService.downloadFile 403 tekrar denemesi de başarısız: $retryErr',
          );
        }
      }

      // Hata durumunda bozuk yarım dosyayı temizle
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      throw ApiException(
        'Dosya indirilirken hata oluştu: ${dioErr.message}',
        statusCode: dioErr.response?.statusCode,
      );
    } catch (e) {
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      throw ApiException('İndirme tamamlanamadı: $e');
    }
  }
}
