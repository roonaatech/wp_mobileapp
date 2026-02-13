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
  // flutter run                                                  -> Development (localhost/emulator)
  // flutter build apk --release --dart-define=ENV=uat            -> UAT server
  // flutter build apk --release --dart-define=ENV=prod           -> Production server
  
  static const String _androidEmulatorUrl = 'http://10.0.2.2:3000';
  static const String _testServerUrl = 'https://api.workpulse-uat.roonaa.in:3353';
  static const String _iosSimulatorUrl = 'http://localhost:3000';
  static const String _productionUrl = 'https://api-workpulse.roonaa.in:3353';

  // Get the appropriate base URL based on platform and environment
  static String get apiBaseUrl {
    // Check environment flag: 'dev', 'uat', or 'prod'
    // Usage:
    //   flutter run                                    -> Development (localhost/emulator)
    //   flutter build apk --release --dart-define=ENV=uat   -> UAT server
    //   flutter build apk --release --dart-define=ENV=prod  -> Production server
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
    
    // Check if running in release mode
    const bool isReleaseMode = bool.fromEnvironment('dart.vm.product');
    
    // Handle explicit environment flags first (for APK builds)
    if (env == 'prod') {
      return _productionUrl;
    }
    
    if (env == 'uat') {
      return _testServerUrl;
    }
    
    // Development mode (env == 'dev' or default)
    if (!isReleaseMode) {
      // Debug mode - use emulator/simulator addresses
      if (Platform.isAndroid) {
        // Android emulator uses special address for host machine
        return _androidEmulatorUrl;
      } else if (Platform.isIOS) {
        // iOS simulator can use localhost
        return _iosSimulatorUrl;
      }
      // For other platforms in debug
      return _iosSimulatorUrl; // fallback to localhost
    }
    
    // Fallback for release without ENV flag - use production
    return _productionUrl;
  }

  static String getBaseUrl() {
    // Simply use apiBaseUrl which already handles ENV logic
    return '$apiBaseUrl/api';
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

  // Time-off endpoints
  static String get timeOffApply => '$apiBaseUrl/api/timeoff/apply';
  static String get timeOffDetail => '$apiBaseUrl/api/timeoff'; // Append ID: $timeOffDetail/{id}
  
  // APK endpoints
  static String get apkLatest => '$apiBaseUrl/api/apk/latest';
  static String get apkCheckVersion => '$apiBaseUrl/api/apk/check-version';
  static String get apkDownloadLatest => '$apiBaseUrl/api/apk/download/latest';
  
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
  
  // Get environment label for display (based on build-time ENV flag)
  static String get envLabel {
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'prod':
        return 'PROD';
      case 'uat':
        return 'UAT';
      default:
        return 'LOCAL';
    }
  }
  
  // Get environment color code (returns hex value for use in UI)
  static int get envColorValue {
    const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'prod':
        return 0xFF4CAF50; // Green for production
      case 'uat':
        return 0xFFFF9800; // Orange for UAT
      default:
        return 0xFF2196F3; // Blue for local/dev
    }
  }
}
