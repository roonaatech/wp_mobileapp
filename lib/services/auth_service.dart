import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'activity_logger.dart';

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
    print('Attempting login to: $url (Force Local: $forceLocal)');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'forceLocal': forceLocal,
        }),
      );

      final responseData = json.decode(response.body);
      
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
