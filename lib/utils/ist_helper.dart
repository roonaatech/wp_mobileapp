import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';

/// Utility class for timezone conversions and date/time formatting based on application settings
/// The timezone is fetched from the backend's application_timezone setting
/// and stored locally. Falls back to 'Asia/Kolkata' if not configured.
class ISTHelper {
  static const String _timezoneKey = 'app_timezone';
  static const String _defaultTimezone = 'Asia/Kolkata'; // Default fallback
  
  static const String _dateFormatKey = 'app_date_format';
  static const String _timeFormatKey = 'app_time_format';

  static String _dateFormat = 'MMM DD, YYYY';
  static String _timeFormat = '12h';

  static bool _initialized = false;
  static tz.Location? _location;

  /// Initialize timezone database and load saved settings
  /// MUST be called once at app startup before using any other methods
  static Future<void> initialize() async {
    if (!_initialized) {
      tz.initializeTimeZones();

      // Load saved timezone preference
      try {
        final prefs = await SharedPreferences.getInstance();
        final timezoneName = prefs.getString(_timezoneKey) ?? _defaultTimezone;
        _location = tz.getLocation(timezoneName);

        _dateFormat = prefs.getString(_dateFormatKey) ?? 'MMM DD, YYYY';
        _timeFormat = prefs.getString(_timeFormatKey) ?? '12h';
      } catch (e) {
        print('Error loading preferences, using default: $e');
        _location = tz.getLocation(_defaultTimezone);
      }

      _initialized = true;
    }
  }

  /// Update the application format settings (call this when settings change)
  static Future<void> setFormatSettings(String dateFormat, String timeFormat) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dateFormatKey, dateFormat);
      await prefs.setString(_timeFormatKey, timeFormat);
      _dateFormat = dateFormat;
      _timeFormat = timeFormat;
    } catch (e) {
      print('Error setting format settings: $e');
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

  /// Parse a date-time string from the backend.
  /// Detects if the string is an absolute UTC string (contains 'Z' or 'T')
  /// or a pre-formatted app-timezone string (naked YYYY-MM-DD HH:mm:ss).
  static DateTime parseUTCtoAppTimezone(String dateString) {
    if (dateString.isEmpty) return now();
    
    // If it contains a timezone indicator, it's absolute UTC
    if (dateString.contains('Z') || dateString.contains('+')) {
      final utcTime = DateTime.parse(dateString).toUtc();
      return toAppTimezone(utcTime);
    }
    
    // Otherwise, treat as "Already in App Timezone" numbers
    // Construction: "YYYY-MM-DD HH:mm:ss"
    try {
      // Dart's DateTime.parse treats naked strings as Local Time.
      // We want to force it to be treated as numbers matching our target location.
      final local = DateTime.parse(dateString);
      // Construct a TZDateTime with the same numbers but in our _location
      if (_location == null) _location = tz.getLocation(_defaultTimezone);
      
      return tz.TZDateTime(
        _location!,
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
        local.second,
      );
    } catch (e) {
      // Fallback
      return DateTime.parse(dateString);
    }
  }

  // ============================================================================
  // Legacy method names for backward compatibility
  // These now use dynamic timezone instead of hardcoded IST
  // ============================================================================
  static DateTime parseUTCtoIST(String dateString) => parseUTCtoAppTimezone(dateString);
  static DateTime nowIST() => now();
  static DateTime toIST(DateTime utcTime) => toAppTimezone(utcTime);

  static String get dateFormat => _dateFormat;
  static String get timeFormat => _timeFormat;

  // ============================================================================
  // Formatting methods based on Global Settings
  // ============================================================================

  /// Format date according to application settings.
  /// Accepts [DateTime] or [String] (e.g. 'YYYY-MM-DD' or ISO timestamp).
  static String formatDate(dynamic date, {bool omitYear = false}) {
    if (date == null) return '';
    DateTime dt;
    if (date is DateTime) {
      dt = date;
    } else {
      final str = date.toString().trim();
      if (str.isEmpty || str == 'null') return '';
      dt = parseUTCtoAppTimezone(str);
    }

    String pattern;
    switch (_dateFormat) {
      case 'DD/MM/YYYY':
        pattern = omitYear ? 'dd/MM' : 'dd/MM/yyyy';
        break;
      case 'DD-MM-YYYY':
        pattern = omitYear ? 'dd-MM' : 'dd-MM-yyyy';
        break;
      case 'MM/DD/YYYY':
        pattern = omitYear ? 'MM/dd' : 'MM/dd/yyyy';
        break;
      case 'MM-DD-YYYY':
        pattern = omitYear ? 'MM-dd' : 'MM-dd-yyyy';
        break;
      case 'YYYY-MM-DD':
        pattern = omitYear ? 'MM-dd' : 'yyyy-MM-dd';
        break;
      case 'YYYY/MM/DD':
        pattern = omitYear ? 'MM/dd' : 'yyyy/MM/dd';
        break;
      case 'DD MMM YYYY':
        pattern = omitYear ? 'dd MMM' : 'dd MMM yyyy';
        break;
      case 'DD MMM, YYYY':
        pattern = omitYear ? 'dd MMM' : 'dd MMM, yyyy';
        break;
      case 'MMM DD, YYYY':
      default:
        pattern = omitYear ? 'MMM dd' : 'MMM dd, yyyy';
        break;
    }

    return DateFormat(pattern).format(dt);
  }

  /// Format time according to application settings.
  /// Accepts [DateTime], [TimeOfDay], or [String] (e.g. '09:30:00', '14:30', or ISO timestamp).
  static String formatTime(dynamic time) {
    if (time == null) return '';
    DateTime dt;
    if (time is DateTime) {
      dt = time;
    } else if (time is TimeOfDay) {
      dt = DateTime(2000, 1, 1, time.hour, time.minute);
    } else {
      final str = time.toString().trim();
      if (str.isEmpty || str == 'null') return '';
      // If time string is HH:mm:ss or HH:mm
      if (str.contains(':') && !str.contains('T') && !str.contains(' ') && !str.contains('-')) {
        final parts = str.split(':');
        final h = int.tryParse(parts[0]) ?? 0;
        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        dt = DateTime(2000, 1, 1, h, m);
      } else {
        dt = parseUTCtoAppTimezone(str);
      }
    }

    if (_timeFormat == '24h') {
      return DateFormat('HH:mm').format(dt);
    } else {
      return DateFormat('hh:mm a').format(dt);
    }
  }

  /// Format date and time according to application settings
  static String formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '';
    DateTime dt;
    if (dateTime is DateTime) {
      dt = dateTime;
    } else {
      final str = dateTime.toString().trim();
      if (str.isEmpty || str == 'null') return '';
      dt = parseUTCtoAppTimezone(str);
    }
    return '${formatDate(dt)} ${formatTime(dt)}';
  }

  /// Format a time range according to application settings
  static String formatTimeRange(dynamic start, dynamic end) {
    final startStr = formatTime(start);
    final endStr = formatTime(end);
    if (startStr.isEmpty) return endStr;
    if (endStr.isEmpty) return startStr;
    return '$startStr – $endStr';
  }
}

