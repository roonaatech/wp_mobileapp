import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ActivityLogger {
  static Future<void> logLogin(String userName) async {
    await _logActivity(
      action: 'LOGIN',
      entity: 'User',
      description: '$userName logged in from mobile',
    );
  }

  static Future<void> logLogout(String userName) async {
    await _logActivity(
      action: 'LOGOUT',
      entity: 'User',
      description: '$userName logged out from mobile',
    );
  }

  static Future<void> logLeaveCreated(String leaveType, String startDate, String endDate) async {
    await _logActivity(
      action: 'CREATE',
      entity: 'LeaveRequest',
      description: 'Leave request created: $leaveType from $startDate to $endDate',
    );
  }

  static Future<void> logOnDutyStarted(String clientName, String location) async {
    await _logActivity(
      action: 'CREATE',
      entity: 'OnDutyLog',
      description: 'On-Duty started at $location for $clientName',
    );
  }

  static Future<void> logOnDutyEnded(String activity) async {
    await _logActivity(
      action: 'UPDATE',
      entity: 'OnDutyLog',
      description: '$activity ended',
    );
  }

  static Future<void> _logActivity({
    required String action,
    required String entity,
    required String description,
    String? entityId,
    String? affectedUserId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');

      if (token == null || userId == null) {
        return;
      }

      await http.post(
        Uri.parse('${AppConfig.getBaseUrl()}/api/activities'),
        headers: {
          'Content-Type': 'application/json',
          'x-access-token': token,
        },
        body: json.encode({
          'user_id': userId,
          'action': action,
          'entity': entity,
          'entity_id': entityId,
          'affected_user_id': affectedUserId ?? userId,
          'description': description,
          'user_agent': 'Flutter Mobile App',
        }),
      );
    } catch (e) {
      // Fail silently
    }
  }
}
