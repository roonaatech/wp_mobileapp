import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_config.dart';
import 'activity_logger.dart';

/// Creates an HTTP client that can handle self-signed SSL certificates
http.Client _createHttpClient() {
  final httpClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  return IOClient(httpClient);
}

class AttendanceService with ChangeNotifier {
  final String? token;
  late final http.Client _client;

  AttendanceService({this.token}) {
    _client = _createHttpClient();
  }

  Future<void> applyLeave(String leaveType, DateTime startDate, DateTime endDate, String reason) async {
    final url = AppConfig.leaveApply;
    final DateFormat formatter = DateFormat('yyyy-MM-dd');

    try {
      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'leave_type': leaveType,
          'start_date': formatter.format(startDate),
          'end_date': formatter.format(endDate),
          'reason': reason,
        }),
      );

      if (response.statusCode == 409) {
        final responseBody = json.decode(response.body);
        throw Exception(responseBody['message'] ?? 'You have an overlapping leave application');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String userMessage = 'Failed to apply leave';
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map) {
            if (decoded.containsKey('message')) {
              userMessage = decoded['message'].toString();
            } else if (decoded.containsKey('errors')) {
              final errors = decoded['errors'];
              if (errors is String) {
                userMessage = errors;
              } else if (errors is List) {
                userMessage = errors.map((e) => e.toString()).join('; ');
              } else if (errors is Map) {
                userMessage = errors.values.map((v) => v.toString()).join('; ');
              } else {
                userMessage = decoded.toString();
              }
            } else {
              // Fallback to a compact string representation
              userMessage = decoded.values.map((v) => v.toString()).join('; ');
            }
          } else if (decoded is String) {
            userMessage = decoded;
          }
        } catch (_) {
          // If body is not JSON or parsing fails, use the raw body but trim it
          userMessage = response.body.toString();
        }

        // Ensure message is not empty
        if (userMessage.trim().isEmpty) {
          userMessage = 'Failed to apply leave (status ${response.statusCode})';
        }

        throw Exception(userMessage);
      }
      
      await ActivityLogger.logLeaveCreated(
        leaveType,
        formatter.format(startDate),
        formatter.format(endDate),
      );
      
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<void> applyTimeOff(DateTime date, TimeOfDay startTime, TimeOfDay endTime, String reason) async {
    final url = AppConfig.timeOffApply;
    final DateFormat dateFormatter = DateFormat('yyyy-MM-dd');
    
    // Format TimeOfDay to HH:mm:ss
    final String startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
    final String endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

    try {
      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'date': dateFormatter.format(date),
          'start_time': startStr,
          'end_time': endStr,
          'reason': reason,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        // Try to parse error message
        String message = 'Failed to apply for time-off';
        try {
          final body = json.decode(response.body);
          message = body['message'] ?? message;
        } catch (_) {}
        throw Exception(message);
      }
      
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getDashboardStats() async {
    final url = AppConfig.leaveStats;
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch dashboard stats: ${response.statusCode}');
      }
      
      final stats = json.decode(response.body);
      return stats;
    } catch (error) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAttendanceHistory(String type) async {
    final url = AppConfig.leaveHistory;
    
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch history');
      }
      
      final data = json.decode(response.body);
      return {'items': data['items'] ?? []};
    } catch (error) {
      rethrow;
    }
  }

  Future<List<dynamic>> getMyLeaves() async {
    final url = AppConfig.leaveHistory;
    
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch leave history');
      }
      
      final data = json.decode(response.body);
      return data['items'] ?? [];
    } catch (error) {
      rethrow;
    }
  }

  Future<List<dynamic>> getLeaveTypes() async {
    final url = AppConfig.leaveTypes;
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch leave types');
      }
      
      final data = json.decode(response.body);
      return data['leaveTypes'] ?? [];
    } catch (error) {
      rethrow;
    }
  }

  Future<List<dynamic>> getLeaveTypesForUser() async {
    final url = AppConfig.leaveTypesForUser;
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch leave types');
      }
      
      final data = json.decode(response.body);
      // The endpoint returns leave types directly as an array
      return (data is List) ? data : (data['leaveTypes'] ?? []);
    } catch (error) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getUserLeaveBalance() async {
    final url = AppConfig.userBalance;
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch leave balance');
      }
      
      final data = json.decode(response.body);
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {};
    } catch (error) {
      rethrow;
    }
  }

  Future<void> updateLeave(int id, String leaveType, DateTime startDate, DateTime endDate, String reason) async {
    final url = '${AppConfig.leaveDetail}/$id';
    final DateFormat formatter = DateFormat('yyyy-MM-dd');

    try {
      final response = await _client.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'leave_type': leaveType,
          'start_date': formatter.format(startDate),
          'end_date': formatter.format(endDate),
          'reason': reason,
        }),
      );

      if (response.statusCode == 409) {
        final responseBody = json.decode(response.body);
        throw Exception(responseBody['message'] ?? 'You have an overlapping leave application');
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to update leave: ${response.statusCode} - ${response.body}');
      }
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<void> updateTimeOff(int id, DateTime date, TimeOfDay startTime, TimeOfDay endTime, String reason) async {
    final url = '${AppConfig.timeOffDetail}/$id';
    final DateFormat dateFormatter = DateFormat('yyyy-MM-dd');

    // Format TimeOfDay to HH:mm:ss
    final String startStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:00';
    final String endStr = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}:00';

    try {
      final response = await _client.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'date': dateFormatter.format(date),
          'start_time': startStr,
          'end_time': endStr,
          'reason': reason,
        }),
      );

      if (response.statusCode != 200) {
        String message = 'Failed to update time-off';
        try {
          final body = json.decode(response.body);
          message = body['message'] ?? message;
        } catch (_) {}
        throw Exception(message);
      }
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  // Check-in and check-out methods commented out - not currently used in app
  // Future<void> checkIn() async {
  //   final url = AppConfig.checkIn;
  //   try {
  //     final response = await _client.post(
  //       Uri.parse(url),
  //       headers: {
  //         'Content-Type': 'application/json',
  //         'x-access-token': token!,
  //       },
  //       body: json.encode({
  //         'latitude': '0.0',
  //         'longitude': '0.0',
  //       }),
  //     );

  //     if (response.statusCode != 200) {
  //       throw Exception('Failed to check in');
  //     }
  //     notifyListeners();
  //   } catch (error) {
  //     rethrow;
  //   }
  // }

  // Future<void> checkOut() async {
  //   final url = AppConfig.checkOut;
  //   try {
  //     final response = await _client.post(
  //       Uri.parse(url),
  //       headers: {
  //         'Content-Type': 'application/json',
  //         'x-access-token': token!,
  //       },
  //       body: json.encode({
  //         'latitude': '0.0',
  //         'longitude': '0.0',
  //       }),
  //     );

  //     if (response.statusCode != 200) {
  //       throw Exception('Failed to check out');
  //     }
  //     notifyListeners();
  //   } catch (error) {
  //     rethrow;
  //   }
  // }

  Future<void> startOnDuty(String clientName, String location, String purpose) async {
    final url = AppConfig.onDutyStart;
    try {
      // Get current location
      Position? position;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          print('Location services are disabled.');
        }
        
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
          print('Location permissions are denied.');
        } else {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
        }
      } catch (e) {
        print('Error getting location: $e');
      }

      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'client_name': clientName,
          'location': location,
          'purpose': purpose,
          'latitude': position?.latitude.toString() ?? '0.0',
          'longitude': position?.longitude.toString() ?? '0.0',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to start on-duty');
      }
      await ActivityLogger.logOnDutyStarted(clientName, location);
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<void> endOnDuty() async {
    final url = AppConfig.onDutyEnd;
    try {
      // Get current location
      Position? position;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          print('Location services are disabled.');
        }
        
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
          print('Location permissions are denied.');
        } else {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
        }
      } catch (e) {
        print('Error getting location: $e');
      }

      final response = await _client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'latitude': position?.latitude.toString() ?? '0.0',
          'longitude': position?.longitude.toString() ?? '0.0',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to end on-duty');
      }
      await ActivityLogger.logOnDutyEnded('On-Duty');
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getActiveOnDuty() async {
    final url = AppConfig.onDutyActive;
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch active on-duty status');
      }
      
      return json.decode(response.body);
    } catch (error) {
      rethrow;
    }
  }

  Future<void> updateOnDutyDetails(int id, String clientName, String location, String purpose) async {
    final url = '${AppConfig.onDutyDetail}/$id';
    try {
      final response = await _client.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
        body: json.encode({
          'client_name': clientName,
          'location': location,
          'purpose': purpose,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update on-duty details');
      }
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }

  Future<void> testNetworkConnection() async {
    print('\n🧪 ========== NETWORK TEST STARTED ==========');
    try {
      final testUrl = Uri.parse('${AppConfig.getBaseUrl()}/leave/test-connection');
      print('🧪 Testing connection to: $testUrl');
      
      final response = await _client.get(
        testUrl,
        headers: {'x-access-token': token ?? 'no-token'},
      ).timeout(const Duration(seconds: 10));
      
      print('🧪 Test request completed with status: ${response.statusCode}');
      print('🧪 Test response body: ${response.body}');
    } catch (e) {
      print('🧪 Test request failed: $e');
    }
    print('🧪 ========== NETWORK TEST ENDED ==========\n');
  }

  Future<void> deleteLeaveOrOnDuty(int id, {bool isOnDuty = false, bool isTimeOff = false}) async {
    if (token == null) {
      throw Exception('Not authenticated');
    }

    // Use the same URL pattern as updateLeave, updateOnDuty, and updateTimeOff
    String urlString;
    if (isTimeOff) {
      urlString = '${AppConfig.timeOffDetail}/$id';
    } else if (isOnDuty) {
      urlString = '${AppConfig.onDutyDetail}/$id';
    } else {
      urlString = '${AppConfig.leaveDetail}/$id';
    }
    
    final url = Uri.parse(urlString);
    
    try {
      final response = await _client.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token!,
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('DELETE request timeout');
        }
      );

      if (response.statusCode != 200) {
        try {
          final responseData = json.decode(response.body);
          throw Exception(responseData['message'] ?? 'Failed to delete request.');
        } catch (e) {
          throw Exception('Failed to delete request. Status: ${response.statusCode}');
        }
      }
      
      notifyListeners();
    } catch (error) {
      rethrow;
    }
  }
}
