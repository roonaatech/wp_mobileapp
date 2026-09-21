import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper to generate, persist, and provide a stable device ID and metadata
/// for mobile attendance security and single-device binding.
class DeviceHelper {
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;

  /// Get or create a persistent device ID (e.g. "wp-dev-app-...")
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString('wp_device_id');
      if (storedId != null && storedId.isNotEmpty) {
        _cachedDeviceId = storedId;
        return storedId;
      }

      // Generate a new hardware-seeded device ID
      final deviceInfo = DeviceInfoPlugin();
      String hardwareSeed = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        hardwareSeed = '${androidInfo.id}_${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        hardwareSeed = iosInfo.identifierForVendor ?? iosInfo.model;
      }

      final cleanSeed = hardwareSeed.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newId = 'wp-dev-app-$cleanSeed-$timestamp';

      await prefs.setString('wp_device_id', newId);
      _cachedDeviceId = newId;
      return newId;
    } catch (e) {
      print('[DeviceHelper] Error getting device ID: $e');
      final fallbackId = 'wp-dev-fallback-${DateTime.now().millisecondsSinceEpoch}';
      _cachedDeviceId = fallbackId;
      return fallbackId;
    }
  }

  /// Get a friendly device model and OS name (e.g. "Samsung SM-S911B (Android 14)")
  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null && _cachedDeviceName!.isNotEmpty) {
      return _cachedDeviceName!;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedDeviceName = '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceName = '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      } else {
        _cachedDeviceName = 'Mobile App Device';
      }
    } catch (_) {
      _cachedDeviceName = 'Mobile App Device';
    }

    return _cachedDeviceName!;
  }
}
