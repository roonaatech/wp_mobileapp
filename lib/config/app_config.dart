import 'dart:io';

class AppConfig {
  // ============================================
  // BACKEND CONFIGURATION - CHANGE URL HERE ONLY
  // ============================================
  // For Android Emulator: http://10.0.2.2:3000
  // For iOS Simulator: http://localhost:3000
  // For Physical Device: http://192.168.x.x:3000 (your computer's IP)
  // For Production: https://api.roonaa.in:3343
  
  static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
  static const String _physicalDeviceUrl = 'http://10.2.1.113:3000';
  static const String _iosSimulatorUrl = 'http://localhost:3000';
  static const String _productionUrl = 'https://api.roonaa.in:3343';

  // Get the appropriate base URL based on platform and environment
  static String get apiBaseUrl {
    // For production/release builds, use production server
    // For development/debug builds, use local/emulator URLs
    
    // Check if running in release mode
    const bool isReleaseMode = bool.fromEnvironment('dart.vm.product');
    
    if (isReleaseMode) {
      // Production - use deployed server
      return _productionUrl;
    }
    
    // Development/Debug mode - use local URLs
    if (Platform.isAndroid) {
      // Use emulator URL for Android
      return _androidEmulatorUrl;
    } else if (Platform.isIOS) {
      // Use simulator URL for iOS
      return _iosSimulatorUrl;
    }
    return _physicalDeviceUrl;
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
  static const String appName = 'ABiS WorkPulse';
  static const String appVersion = '1.0.0';
  static const String appBuild = '1';
  
  // ============================================
  // ENVIRONMENT
  // ============================================
  static const String environment = 'development'; // Change to 'production' when deploying
  static bool get isProduction => environment == 'production';
  static bool get isDevelopment => environment == 'development';
}
