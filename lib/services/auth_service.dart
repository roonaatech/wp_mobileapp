import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import 'activity_logger.dart';

/// Creates an HTTP client that can handle self-signed SSL certificates
http.Client _createHttpClient() {
  final httpClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  return IOClient(httpClient);
}

class AuthConfirmationException implements Exception {
  final String message;
  AuthConfirmationException(this.message);
  @override
  String toString() => message;
}

class AuthSetupRequiredException implements Exception {
  final String message;
  AuthSetupRequiredException(this.message);
  @override
  String toString() => message;
}

class AppUpdateRequiredException implements Exception {
  final String message;
  final String currentVersion;
  final String latestVersion;
  final String? releaseNotes;
  final String downloadUrl;
  
  AppUpdateRequiredException({
    required this.message,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes,
    required this.downloadUrl,
  });
  
  @override
  String toString() => message;
}

class AuthService with ChangeNotifier {
  String? _token;
  String? _userId;
  String? _userName;
  
  bool get isAuth {
    return _token != null;
  }

  String? get token {
    return _token;
  }

  String? get userName {
    return _userName;
  }

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('token')) {
      return false;
    }
    _token = prefs.getString('token');
    _userName = prefs.getString('userName') ?? 'User';
    notifyListeners();
    return true;
  }

  String? get _baseUrl {
    return null; // Using AppConfig instead
  }

  Future<void> login(String email, String password, {bool forceLocal = false}) async {
    final url = AppConfig.authSignIn;
    
    // Check if running in debug/development mode
    // In release mode, dart.vm.product is true
    // USE_LOCALHOST defaults to true for debug, but in release builds it's effectively false
    const bool isReleaseMode = bool.fromEnvironment('dart.vm.product');
    const bool useLocalhost = bool.fromEnvironment('USE_LOCALHOST', defaultValue: true);
    
    // Skip version check only in debug mode when using localhost
    // In release mode (isReleaseMode=true), always perform version check
    final bool skipVersionCheck = !isReleaseMode && useLocalhost;
    
    // Get current app version (only needed for release builds)
    String? appVersion;
    if (!skipVersionCheck) {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        // Include build number: "1.3.0+7" format
        appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      } catch (e) {
        print('Could not get package info: $e');
        // Fallback to config version without build number
        appVersion = AppConfig.appVersion;
      }
    }
    
    print('Attempting login to: $url (Force Local: $forceLocal, App Version: ${appVersion ?? "skipped (dev mode)"}, Release: $isReleaseMode)');    final client = _createHttpClient();
    try {
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'forceLocal': forceLocal,
          'is_mobile_app': true,
          if (appVersion != null) 'app_version': appVersion,
        }),
      );

      final responseData = json.decode(response.body);
      
      // Handle App Update Required (HTTP 426 Upgrade Required)
      if (response.statusCode == 426 && responseData['updateRequired'] == true) {
        throw AppUpdateRequiredException(
          message: responseData['message'] ?? 'App update required.',
          currentVersion: responseData['currentVersion'] ?? appVersion,
          latestVersion: responseData['latestVersion'] ?? 'Unknown',
          releaseNotes: responseData['releaseNotes'],
          downloadUrl: '${AppConfig.apiBaseUrl}${responseData['downloadUrl'] ?? '/api/apk/download/latest'}',
        );
      }
      
      // Handle Confirmation Request from Backend
      if (response.statusCode == 200 && responseData['requiresConfirmation'] == true) {
        throw AuthConfirmationException(responseData['message'] ?? 'External authentication unavailable.');
      }

      if (response.statusCode != 200) {
        throw Exception(responseData['message']);
      }

      // Check for Setup Required (Role or Gender missing)
      final role = responseData['role'];
      final gender = responseData['gender'];

      // Helper to check if role/gender is invalid
      // Role: null or 0 means invalid
      // Gender: null or empty string means invalid
      final isRoleInvalid = role == null || role == 0 || role == '0';
      final isGenderInvalid = gender == null || gender == '';

      if (isRoleInvalid || isGenderInvalid) {
         throw AuthSetupRequiredException("Setup Required");
      }

      _token = responseData['accessToken'];
      _userId = responseData['id'].toString();
      _userName = '${responseData['firstname'] ?? ''} ${responseData['lastname'] ?? ''}'.trim();
      
      final prefs = await SharedPreferences.getInstance();
      final userData = json.encode({
        'token': _token,
        'userId': _userId,
        'userName': _userName,
      });
      prefs.setString('userData', userData);
      prefs.setString('token', _token!);
      prefs.setString('userId', _userId!);
      
      // Log activity
      await ActivityLogger.logLogin(_userName ?? 'User');
      
      notifyListeners();
    } catch (error) {
      print('Login Error: $error');
      rethrow;
    }
  }

  void logout() async {
    final userName = _userName ?? 'User';
    final token = _token;
    
    _token = null;
    _userId = null;
    _userName = null;
    
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('userData');
    prefs.remove('token');
    prefs.remove('userId');
    
    // Call backend logout endpoint to log activity server-side
    if (token != null) {
      try {
        await http.post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'x-access-token': token,
          },
        );
      } catch (error) {
        print('Logout backend call error: $error');
      }
    }
    
    // Log activity via mobile logger
    await ActivityLogger.logLogout(userName);
    
    notifyListeners();
  }
}
