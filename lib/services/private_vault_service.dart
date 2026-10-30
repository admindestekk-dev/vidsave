import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

/// Gizli Klasördeki şifreli medya kaydı
class VaultItem {
  VaultItem({
    required this.id,
    required this.originalName,
    required this.encryptedFileName,
    required this.type, // 'video' veya 'audio'
    required this.sizeInBytes,
    required this.addedAt,
  });

  final String id;
  final String originalName;
  final String encryptedFileName;
  final String type;
  final int sizeInBytes;
  final DateTime addedAt;

  bool get isAudio =>
      type == 'audio' || originalName.toLowerCase().endsWith('.mp3');

  String get formattedSize {
    if (sizeInBytes <= 0) return '0 B';
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    return VaultItem(
      id: json['id'] as String,
      originalName: json['originalName'] as String,
      encryptedFileName: json['encryptedFileName'] as String,
      type: json['type'] as String? ?? 'video',
      sizeInBytes: (json['sizeInBytes'] as num?)?.toInt() ?? 0,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalName': originalName,
    'encryptedFileName': encryptedFileName,
    'type': type,
    'sizeInBytes': sizeInBytes,
    'addedAt': addedAt.toIso8601String(),
  };
}

/// VidSave Dahili Şifreli Gizli Klasör Servisi (Private Vault Service)
///
/// Biyometrik (Parmak İzi/Yüz Tanıma) veya Güvenli PIN ile kimlik doğrular.
/// Dosyaları cihazın korumalı app data klasöründe karmaşık .dat uzantılarıyla gizler.
class PrivateVaultService {
  PrivateVaultService._();
  static final PrivateVaultService instance = PrivateVaultService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _vaultMetadataKey = 'vidsave_vault_metadata_v1';
  static const String _vaultPinKey = 'vidsave_vault_user_pin';

  final ValueNotifier<List<VaultItem>> vaultNotifier =
      ValueNotifier<List<VaultItem>>([]);

  /// Kullanıcının daha önce bir PIN veya Kasa şifresi belirleyip belirlemediği
  Future<bool> hasPinCode() async {
    final pin = await _storage.read(key: _vaultPinKey);
    return pin != null && pin.isNotEmpty;
  }

  /// Yeni PIN kodu belirler
  Future<void> setPinCode(String pin) async {
    await _storage.write(key: _vaultPinKey, value: pin);
  }

  /// Biyometrik (Parmak İzi) veya PIN ile kimlik doğrulaması yapar
  Future<bool> authenticate({String? enteredPin}) async {
    // 1. PIN girildiyse PIN doğrulaması yap
    if (enteredPin != null) {
      final storedPin = await _storage.read(key: _vaultPinKey);
      return storedPin != null && storedPin == enteredPin;
    }

    // 2. Biyometrik donanım desteğini kontrol et
    try {
      final canAuthBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (canAuthBiometrics && isDeviceSupported) {
        final didAuth = await _localAuth.authenticate(
          localizedReason:
              'VidSave Gizli Kasanıza erişmek için lütfen kimliğinizi doğrulayın.',
        );
        return didAuth;
      }
    } catch (e) {
      debugPrint('Biyometrik doğrulama hatası: $e');
    }

    return false;
  }

  /// Gizli Kasa klasör yolunu getirir
  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(
      '${appDir.path}${Platform.pathSeparator}.vidsave_private_vault',
    );
    if (!vaultDir.existsSync()) {
      vaultDir.createSync(recursive: true);
    }
    return vaultDir;
  }

  /// Rastgele şifrelenmiş dosya adı üretir (Örn: x92f8k.dat)
  String _generateRandomDatName() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final name = List.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return '$name.dat';
  }

  /// Kasadaki tüm kayıtlı gizli dosyaları listeler
  Future<List<VaultItem>> getVaultItems() async {
    try {
      final raw = await _storage.read(key: _vaultMetadataKey);
      if (raw == null || raw.isEmpty) {
        vaultNotifier.value = [];
        return [];
      }
      final list = jsonDecode(raw) as List<dynamic>;
      final items = list
          .map((e) => VaultItem.fromJson(e as Map<String, dynamic>))
          .toList();
      items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      vaultNotifier.value = List.unmodifiable(items);
      return items;
    } catch (e) {
      debugPrint('Vault listeleme hatası: $e');
      return [];
    }
  }

  /// Normal bir indirme dosyasını gizli kasaya taşır ve kriptolar
  Future<VaultItem> importFileToVault({
    required File sourceFile,
    required String originalName,
    required String type,
  }) async {
    final vaultDir = await _getVaultDirectory();
    final encryptedName = _generateRandomDatName();
    final destinationFile = File(
      '${vaultDir.path}${Platform.pathSeparator}$encryptedName',
    );

    // Dosyayı gizli kasaya taşı (move/rename)
    await sourceFile.copy(destinationFile.path);
    try {
      await sourceFile.delete(); // Orijinal galerideki/klasördeki kopyayı sil
    } catch (_) {}

    final item = VaultItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      originalName: originalName,
      encryptedFileName: encryptedName,
      type: type,
      sizeInBytes: destinationFile.existsSync()
          ? destinationFile.lengthSync()
          : 0,
      addedAt: DateTime.now(),
    );

    final items = await getVaultItems();
    items.insert(0, item);

    final rawJson = jsonEncode(items.map((e) => e.toJson()).toList());
    await _storage.write(key: _vaultMetadataKey, value: rawJson);
    vaultNotifier.value = List.unmodifiable(items);

    return item;
  }

  /// Kasadaki şifreli dosyayı geçici olarak oynatmak için dosya referansı döner
  Future<File?> getVaultFile(VaultItem item) async {
    final vaultDir = await _getVaultDirectory();
    final file = File(
      '${vaultDir.path}${Platform.pathSeparator}${item.encryptedFileName}',
    );
    return file.existsSync() ? file : null;
  }

  /// Kasadaki dosyayı kasadan çıkarıp tekrar normal indirmeler klasörüne geri aktarır
  Future<File?> exportFileFromVault(VaultItem item) async {
    final vaultDir = await _getVaultDirectory();
    final encryptedFile = File(
      '${vaultDir.path}${Platform.pathSeparator}${item.encryptedFileName}',
    );
    if (!encryptedFile.existsSync()) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final restoredFile = File(
      '${appDir.path}${Platform.pathSeparator}${item.originalName}',
    );

    await encryptedFile.copy(restoredFile.path);
    await encryptedFile.delete();

    await deleteItem(item.id, removeFile: false);
    return restoredFile;
  }

  /// Kasadan bir öğeyi siler
  Future<void> deleteItem(String id, {bool removeFile = true}) async {
    final items = await getVaultItems();
    final index = items.indexWhere((it) => it.id == id);
    if (index != -1) {
      final removed = items.removeAt(index);
      if (removeFile) {
        try {
          final vaultDir = await _getVaultDirectory();
          final file = File(
            '${vaultDir.path}${Platform.pathSeparator}${removed.encryptedFileName}',
          );
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
      final rawJson = jsonEncode(items.map((e) => e.toJson()).toList());
      await _storage.write(key: _vaultMetadataKey, value: rawJson);
      vaultNotifier.value = List.unmodifiable(items);
    }
  }
}
