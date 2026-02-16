import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

/// Utility class for timezone conversions based on application settings
/// The timezone is fetched from the backend's application_timezone setting
/// and stored locally. Falls back to 'Asia/Kolkata' if not configured.
class ISTHelper {
  static const String _timezoneKey = 'app_timezone';
  static const String _defaultTimezone = 'Asia/Kolkata'; // Default fallback
  static bool _initialized = false;
  static tz.Location? _location;

  /// Initialize timezone database and load saved timezone
  /// MUST be called once at app startup before using any other methods
  static Future<void> initialize() async {
    if (!_initialized) {
      tz.initializeTimeZones();

      // Load saved timezone preference
      try {
        final prefs = await SharedPreferences.getInstance();
        final timezoneName = prefs.getString(_timezoneKey) ?? _defaultTimezone;
        _location = tz.getLocation(timezoneName);
      } catch (e) {
        print('Error loading timezone preference, using default: $e');
        _location = tz.getLocation(_defaultTimezone);
      }

      _initialized = true;
    }
  }

  /// Update the application timezone (call this when timezone setting changes)
  static Future<void> setTimezone(String timezoneName) async {
    try {
      _location = tz.getLocation(timezoneName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_timezoneKey, timezoneName);
    } catch (e) {
      print('Error setting timezone: $e');
    }
  }

  /// Get current timezone name
  static String getTimezoneName() {
    if (_location == null) {
      print('Warning: ISTHelper not initialized! Call initialize() at app startup.');
      return _defaultTimezone;
    }
    return _location!.name;
  }

  /// Convert UTC DateTime to application's configured timezone
  static DateTime toAppTimezone(DateTime utcTime) {
    if (_location == null) {
      print('Warning: ISTHelper not initialized! Call initialize() at app startup.');
      _location = tz.getLocation(_defaultTimezone);
    }
    return tz.TZDateTime.from(utcTime, _location!);
  }

  /// Get current time in application's configured timezone
  static DateTime now() {
    if (_location == null) {
      print('Warning: ISTHelper not initialized! Call initialize() at app startup.');
      _location = tz.getLocation(_defaultTimezone);
    }
    return tz.TZDateTime.now(_location!);
  }

  /// Parse UTC string and convert to application's configured timezone
  static DateTime parseUTCtoAppTimezone(String utcString) {
    final utcTime = DateTime.parse(utcString).toUtc();
    return toAppTimezone(utcTime);
  }

  // ============================================================================
  // Legacy method names for backward compatibility
  // These now use dynamic timezone instead of hardcoded IST
  // ============================================================================

  /// @deprecated Use toAppTimezone instead
  static DateTime toIST(DateTime utcTime) => toAppTimezone(utcTime);

  /// @deprecated Use now instead
  static DateTime nowIST() => now();

  /// @deprecated Use parseUTCtoAppTimezone instead - still works with old name
  static DateTime parseUTCtoIST(String utcString) => parseUTCtoAppTimezone(utcString);
}
