import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/app_update_service.dart';

/// Arka planda veya uygulama kapalıyken gelen Firebase bildirimlerini işleyen
/// üst düzey (top-level) izole fonksiyonu.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint(
    'FirebaseNotificationService [Arka Plan]: Bildirim alındı ID: ${message.messageId}, Data: ${message.data}',
  );
  // Arka planda veri mesajı geldiyse yerel bildirim göstermek için initialize çağrısı yapılabilir
  if (message.notification == null && message.data.isNotEmpty) {
    await FirebaseNotificationService.instance.showNotificationFromRemote(
      message,
    );
  }
}

/// Firebase Cloud Messaging (FCM) ve Play Store Güncelleme Bildirimleri Servisi.
///
/// Firebase konsolundan veya API üzerinden gönderilen bildirimlerde:
/// - `action: "update"` veya `type: "update"`
/// - `store_url: "https://play.google.com/..."` (veya doğrudan Play Store linki)
/// - `force_update: "true" / "false"`
/// - `version: "1.0.1"`
/// gibi parametreleri dinler, kullanıcı bildirime dokunduğunda doğrudan
/// Play Store sayfasını açar veya uygulama içi güncelleme isteğini tetikler.
class FirebaseNotificationService {
  FirebaseNotificationService._();

  static final FirebaseNotificationService instance =
      FirebaseNotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _fcmToken;

  /// Bildirim kanalı sabitleri
  static const String updateChannelId = 'vidsave_updates_channel';
  static const String updateChannelName =
      'Uygulama Güncellemeleri ve Duyurular';
  static const String updateChannelDesc =
      'Yeni sürüm güncellemeleri ve önemli uygulama bildirimleri';

  /// FCM Token
  String? get fcmToken => _fcmToken;

  /// Servisi başlatır, bildirim izinlerini alır ve dinleyicileri ayarlar.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1. Firebase Core güvencesi
      try {
        await Firebase.initializeApp();
      } catch (_) {}

      // 2. Arka plan FCM yöneticisi kaydı
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 3. Yerel bildirim kanalını yapılandır
      await _setupLocalNotificationChannel();

      // 4. Bildirim izni iste (Android 13+ ve iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        'FirebaseNotificationService: FCM Bildirim İzni Durumu: ${settings.authorizationStatus}',
      );

      // 5. FCM Token al ve logla (konsoldan test gönderebilmek için)
      try {
        // ignore: deprecated_member_use
        _fcmToken = await _fcm.getToken();
        debugPrint('FirebaseNotificationService FCM Token: $_fcmToken');
      } catch (tokenErr) {
        debugPrint('FirebaseNotificationService Token alınamadı: $tokenErr');
      }

      // Token yenilenirse yakala
      // ignore: deprecated_member_use
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint(
          'FirebaseNotificationService FCM Token yenilendi: $newToken',
        );
      });

      // Genel duyuru / güncelleme konusuna otomatik abone ol
      try {
        await _fcm.subscribeToTopic('updates');
        await _fcm.subscribeToTopic('all_users');
      } catch (topicErr) {
        debugPrint('FCM topic abonelik hatası: $topicErr');
      }

      // 6. Ön planda gelen bildirimleri dinle (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'FirebaseNotificationService [Ön Plan]: Mesaj geldi: ${message.messageId}',
        );
        _handleForegroundMessage(message);
      });

      // 7. Arka plandayken bildirime tıklanıp uygulama açıldığında
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
          'FirebaseNotificationService [Tıklandı - Arka Plan]: ${message.messageId}',
        );
        _handleNotificationAction(message.data);
      });

      // 8. Uygulama tamamen kapalıyken bildirime tıklanıp açıldığında (Terminated)
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          'FirebaseNotificationService [Tıklandı - Kapalı Açılış]: ${initialMessage.messageId}',
        );
        _handleNotificationAction(initialMessage.data);
      }

      _initialized = true;
    } catch (e, st) {
      debugPrint('FirebaseNotificationService başlatma hatası: $e\n$st');
    }
  }

  /// Android bildirim kanalı ve FlutterLocalNotifications ilklendirmesi
  Future<void> _setupLocalNotificationChannel() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = jsonDecode(payload);
            if (data is Map<String, dynamic>) {
              _handleNotificationAction(data);
            }
          } catch (e) {
            debugPrint('LocalNotification payload decode hatası: $e');
          }
        }
      },
    );

    // Android için yüksek öncelikli güncelleme kanalı oluştur
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        updateChannelId,
        updateChannelName,
        description: updateChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  /// Ön plandayken gelen mesajı şık bir yerel bildirim olarak bas
  void _handleForegroundMessage(RemoteMessage message) {
    showNotificationFromRemote(message);
  }

  /// Uzak bildirimden sistem tepsisinde bildirim gösterir
  Future<void> showNotificationFromRemote(RemoteMessage message) async {
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'VidSave Yeni Güncelleme Yayında!';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'Yeni özellikler ve hız iyileştirmeleri için şimdi güncelleyin.';

    final androidDetails = AndroidNotificationDetails(
      updateChannelId,
      updateChannelName,
      channelDescription: updateChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }

  /// Bildirime tıklandığında gelen aksiyonu yorumlar:
  /// Play Store linki varsa veya type: 'update' ise doğrudan mağazaya veya güncellemeye yönlendirir.
  Future<void> _handleNotificationAction(Map<String, dynamic> data) async {
    debugPrint('FirebaseNotificationService aksiyon işleniyor: $data');

    // 1. Doğrudan özel URL veya Play Store linki verilmişse
    final customUrl =
        data['store_url']?.toString() ??
        data['url']?.toString() ??
        data['play_store_url']?.toString();

    if (customUrl != null && customUrl.trim().isNotEmpty) {
      try {
        final uri = Uri.parse(customUrl.trim());
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        debugPrint('Özel mağaza bağlantısı açılamadı: $e');
      }
    }

    // 2. Güncelleme tipi gelmişse AppUpdateService üzerinden Play Store aç
    final action = data['action']?.toString().toLowerCase();
    final type = data['type']?.toString().toLowerCase();

    if (action == 'update' || type == 'update' || action == 'upgrade') {
      await AppUpdateService.instance.openPlayStore();
      return;
    }

    // 3. Genel fallback: Varsayılan Play Store bağlantısını aç
    if (data.containsKey('open_store') &&
        data['open_store'].toString().toLowerCase() == 'true') {
      await AppUpdateService.instance.openPlayStore();
    }
  }
}
