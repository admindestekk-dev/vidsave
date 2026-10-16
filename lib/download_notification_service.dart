import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service to display system download progress and completion notifications.
class DownloadNotificationService {
  DownloadNotificationService._();

  static final DownloadNotificationService instance =
      DownloadNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _nextNotificationId = 100;

  static const String _channelId = 'vidsave_downloads';
  static const String _channelName = 'İndirme Bildirimleri';
  static const String _channelDescription =
      'Video ve ses dosyası indirme ilerleme durumu';

  /// Generates a unique notification id for each download session.
  int allocateNotificationId() {
    _nextNotificationId++;
    if (_nextNotificationId > 100000) _nextNotificationId = 100;
    return _nextNotificationId;
  }

  bool get _isSupportedPlatform =>
      !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Initializes the local notification plugin and requests notification
  /// permissions on Android 13+. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    if (!_isSupportedPlatform) return;

    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );

      await _plugin.initialize(settings: initSettings);

      if (Platform.isAndroid) {
        final androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('DownloadNotificationService initialization error: $e');
    }
  }

  /// Shows or updates an ongoing download notification with progress percentage.
  Future<void> showProgress({
    required int id,
    required String title,
    int? percent,
  }) async {
    if (!_isSupportedPlatform) return;
    try {
      await initialize();

      final isIndeterminate = percent == null;
      final body = isIndeterminate ? 'İndiriliyor…' : '%$percent indirildi';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: percent ?? 0,
        indeterminate: isIndeterminate,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      );

      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showProgress error: $e');
    }
  }

  /// Updates the notification when the download is completed.
  Future<void> showCompleted({
    required int id,
    required String title,
    required String fileName,
  }) async {
    if (!_isSupportedPlatform) return;
    try {
      await initialize();

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showProgress: false,
        ongoing: false,
        autoCancel: true,
        onlyAlertOnce: false,
        playSound: true,
      );

      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        id: id,
        title: title,
        body: 'İndirme tamamlandı: $fileName',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showCompleted error: $e');
    }
  }

  /// Updates or cancels the notification if an error occurred.
  Future<void> showError({
    required int id,
    required String title,
    String? error,
  }) async {
    if (!_isSupportedPlatform) return;
    try {
      await initialize();

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        showProgress: false,
        ongoing: false,
        autoCancel: true,
      );

      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        id: id,
        title: title,
        body: error ?? 'İndirme tamamlanamadı.',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('DownloadNotificationService showError error: $e');
    }
  }

  /// Cancels a specific notification by id.
  Future<void> cancel(int id) async {
    if (!_isSupportedPlatform) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('DownloadNotificationService cancel error: $e');
    }
  }
}
