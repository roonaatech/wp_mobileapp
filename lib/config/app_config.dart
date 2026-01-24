import 'dart:io';

class AppConfig {
  // ============================================
  // BACKEND CONFIGURATION - CHANGE URL HERE ONLY
  // ============================================
  // For Android Emulator: http://10.0.2.2:3000
  // For iOS Simulator: http://localhost:3000
  // For Physical Device: http://192.168.x.x:3000 (your computer's IP)
  // For Production: https://api.roonaa.in:3343
  //
  // USAGE:
  // flutter run                                           -> Uses localhost:3000 (USE_LOCALHOST=true by default)
  // flutter build apk --debug --dart-define=USE_LOCALHOST=false  -> Uses test server
  // flutter build apk --release                           -> Uses production server
  
  static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
  static const String _testServerUrl = 'https://api.workpulse-uat.roonaa.in:3353';
  static const String _iosSimulatorUrl = 'http://localhost:3000';
  static const String _productionUrl = 'https://api.workpulse-uat.roonaa.in:3353';

  // Get the appropriate base URL based on platform and environment
  static String get apiBaseUrl {
    // Check if running in release mode
    const bool isReleaseMode = bool.fromEnvironment('dart.vm.product');
    
    // Check for USE_LOCALHOST flag (set when running flutter run with --dart-define)
    const bool useLocalhost = bool.fromEnvironment('USE_LOCALHOST', defaultValue: true);
    
    if (isReleaseMode) {
      // Production - use deployed server
      return _productionUrl;
    }
    
    // Debug mode - check if we should use localhost
    if (useLocalhost) {
      // When running "flutter run" (default behavior)
      if (Platform.isAndroid) {
        // Android emulator uses special address for host machine
        return _androidEmulatorUrl;
      } else if (Platform.isIOS) {
        // iOS simulator can use localhost
        return _iosSimulatorUrl;
      }
      // For other platforms in debug with localhost flag
      return _iosSimulatorUrl; // fallback to localhost
    }
    
    // When building APK or explicitly setting USE_LOCALHOST=false
    return _testServerUrl;
  }

  static String getBaseUrl() {
    // For Production: https://api.roonaa.in:3343
    // Use your computer's IP for physical device testing.
    const String devIp = '10.2.1.113'; // Example: '192.168.1.5'

    if (Platform.isAndroid) {
      // Android emulator uses a special address to access the host machine
      return 'http://10.0.2.2:3000/api';
    } else if (Platform.isIOS) {
      // iOS simulator can use localhost
      return 'http://localhost:3000/api';
    } else {
      // For macOS/desktop - use localhost since we're on the same machine
      return 'http://localhost:3000/api';
    }
  }

  // ============================================
  // API ENDPOINTS
  // ============================================
  
  static String get authSignIn => '$apiBaseUrl/api/auth/signin';
  static String get authCheck => '$apiBaseUrl/api/auth/check';
  
  // Leave endpoints
  static String get leaveApply => '$apiBaseUrl/api/leave/apply';
  static String get leaveHistory => '$apiBaseUrl/api/leave/my-history';
  static String get leaveDetail => '$apiBaseUrl/api/leave'; // Append ID: $leaveDetail/{id}
  static String get leaveTypes => '$apiBaseUrl/api/leavetypes';
  static String get leaveTypesForUser => '$apiBaseUrl/api/leavetypes/user/filtered';
  static String get leaveStats => '$apiBaseUrl/api/leave/my-stats';
  static String get userBalance => '$apiBaseUrl/api/leave/my-balance';
  
  // On-duty endpoints
  static String get onDutyStart => '$apiBaseUrl/api/onduty/start';
  static String get onDutyEnd => '$apiBaseUrl/api/onduty/end';
  static String get onDutyActive => '$apiBaseUrl/api/onduty/active';
  static String get onDutyDetail => '$apiBaseUrl/api/onduty'; // Append ID: $onDutyDetail/{id}
  
  // ============================================
  // APP METADATA
  // ============================================
  static const String appName = 'WorkPulse';
  static const String appVersion = '1.0.0';
  static const String appBuild = '1';
  
  // ============================================
  // ENVIRONMENT
  // ============================================
  static const String environment = 'development'; // Change to 'production' when deploying
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';
}
