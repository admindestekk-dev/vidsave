import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum DownloadTaskStatus { downloading, paused, completed, failed }

/// Aktif olarak sürmekte olan veya duraklatılmış indirme görevini temsil eder.
class ActiveDownloadTask {
  ActiveDownloadTask({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.totalBytes,
    this.receivedBytes = 0,
    this.progress = 0.0,
    this.speed = '0 KB/s',
    this.status = DownloadTaskStatus.downloading,
    this.cancelToken,
  });

  final String id;
  final String title;
  final String url;
  final String type; // 'video' veya 'audio'
  final String? thumbnailUrl;
  int? totalBytes;
  int receivedBytes;
  double progress;
  String speed;
  DownloadTaskStatus status;
  CancelToken? cancelToken;

  bool get isAudio => type == 'audio' || type == 'mp3';
  bool get isPaused => status == DownloadTaskStatus.paused;
  bool get isDownloading => status == DownloadTaskStatus.downloading;

  String get formattedProgress =>
      '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

  String get formattedSizeInfo {
    final rec = _formatBytes(receivedBytes);
    if (totalBytes != null && totalBytes! > 0) {
      final tot = _formatBytes(totalBytes!);
      return '$rec / $tot';
    }
    return rec;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// VidSave genel indirme yöneticisi singleton'ı.
/// Aktif indirmelerin anlık durumunu UI'a (DownloadsScreen) broadcast eder.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final Map<String, ActiveDownloadTask> _tasks = {};

  /// Dinleyiciye aktif görevlerin listesini fırlatır.
  final ValueNotifier<List<ActiveDownloadTask>> activeTasksNotifier =
      ValueNotifier<List<ActiveDownloadTask>>([]);

  void _notify() {
    activeTasksNotifier.value = List.unmodifiable(_tasks.values.toList());
  }

  ActiveDownloadTask startTask({
    required String id,
    required String title,
    required String url,
    required String type,
    String? thumbnailUrl,
    CancelToken? cancelToken,
  }) {
    final task = ActiveDownloadTask(
      id: id,
      title: title,
      url: url,
      type: type,
      thumbnailUrl: thumbnailUrl,
      cancelToken: cancelToken,
    );
    _tasks[id] = task;
    _notify();
    return task;
  }

  void updateProgress({
    required String id,
    required int received,
    int? total,
    double? progress,
    required String speed,
  }) {
    final task = _tasks[id];
    if (task == null) return;

    task.receivedBytes = received;
    task.totalBytes = total;
    task.progress =
        progress ?? ((total != null && total > 0) ? (received / total) : 0.0);
    task.speed = speed;
    task.status = DownloadTaskStatus.downloading;
    _notify();
  }

  void pauseTask(String id) {
    final task = _tasks[id];
    if (task != null && task.status == DownloadTaskStatus.downloading) {
      task.status = DownloadTaskStatus.paused;
      task.cancelToken?.cancel('Duraklatıldı');
      _notify();
    }
  }

  void resumeTask(String id) {
    final task = _tasks[id];
    if (task != null && task.status == DownloadTaskStatus.paused) {
      task.status = DownloadTaskStatus.downloading;
      task.cancelToken = CancelToken();
      _notify();
    }
  }

  void completeTask(String id) {
    _tasks.remove(id);
    _notify();
  }

  void failTask(String id) {
    final task = _tasks[id];
    if (task != null) {
      task.status = DownloadTaskStatus.failed;
      _notify();
    }
  }

  void cancelTask(String id) {
    final task = _tasks.remove(id);
    task?.cancelToken?.cancel('İptal edildi');
    _notify();
  }
}
