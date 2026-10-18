import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable anonymous identity for this app installation's server-side records.
class UserIdentityService {
  UserIdentityService._();

  static const String _userIdKey = 'vidsave_installation_user_id';
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_userIdKey)?.toLowerCase();
    if (existing != null && _uuidPattern.hasMatch(existing)) {
      return existing;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final userId =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';

    await prefs.setString(_userIdKey, userId);
    return userId;
  }

  static Future<void> clearUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
  }
}
