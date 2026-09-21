import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';

class MyAttendanceBadgeScreen extends StatefulWidget {
  const MyAttendanceBadgeScreen({super.key});

  @override
  State<MyAttendanceBadgeScreen> createState() => _MyAttendanceBadgeScreenState();
}

class _MyAttendanceBadgeScreenState extends State<MyAttendanceBadgeScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _badgeData;
  String? _qrPayload;
  int _remainingSeconds = 5;
  Timer? _countdownTimer;
  Timer? _rotationTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isFetching = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchBadge();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _rotationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchBadge({bool silent = false}) async {
    if (_isFetching && silent) return;
    _isFetching = true;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final response = await service.getMyAttendanceBadge();

      if (!mounted) {
        _isFetching = false;
        return;
      }

      if (response['success'] == true) {
        final Map<String, dynamic> badge = response['badge'] is Map
            ? Map<String, dynamic>.from(response['badge'])
            : <String, dynamic>{};

        final Map<String, dynamic> emp = response['employee'] is Map
            ? Map<String, dynamic>.from(response['employee'])
            : <String, dynamic>{};

        final qr = response['qrPayload']?.toString() ??
            badge['qrPayload']?.toString() ??
            '';

        final dynamic ttlVal = response['ttlSeconds'] ?? badge['ttlSeconds'] ?? 5;
        final int ttl = (ttlVal is num) ? ttlVal.toInt() : int.tryParse(ttlVal.toString()) ?? 5;

        final badgeData = <String, dynamic>{
          'staffId': emp['staffId'] ?? badge['staffId'] ?? response['staffId'],
          'name': emp['name'] ?? badge['name'] ?? response['name'],
          'email': emp['email'] ?? badge['email'] ?? response['email'],
          'role': emp['role'] ?? badge['role'] ?? response['role'],
          'department': emp['department'] ?? badge['department'] ?? response['department'],
          'avatarUrl': emp['avatarUrl'] ?? badge['avatarUrl'] ?? response['avatarUrl'],
          'todayStatus': response['todayStatus'] ?? badge['todayStatus'] ?? 'NOT_CHECKED_IN',
          'checkInTime': response['checkInTime'] ?? badge['checkInTime'],
          'checkOutTime': response['checkOutTime'] ?? badge['checkOutTime'],
          'qrPayload': qr,
          'expiresAt': response['expiresAt'] ?? badge['expiresAt'],
          'ttlSeconds': ttl,
        };

        setState(() {
          _badgeData = badgeData;
          _qrPayload = qr;
          if (!silent) {
            _remainingSeconds = ttl > 0 ? ttl : 5;
          }
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        if (!silent) {
          setState(() {
            _isLoading = false;
            _errorMessage = response['message']?.toString() ?? 'Unable to generate dynamic badge';
          });
        }
      }
    } catch (error) {
      if (!mounted) {
        _isFetching = false;
        return;
      }
      if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      _isFetching = false;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_remainingSeconds <= 1) {
        setState(() {
          _remainingSeconds = 5;
        });
        _fetchBadge(silent: true);
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'CHECKED_IN':
        return const Color(0xFF10B981);
      case 'COMPLETED':
        return const Color(0xFF8B5CF6);
      case 'NOT_CHECKED_IN':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _getStatusText(String? status, String? checkInTime, String? checkOutTime) {
    switch (status) {
      case 'CHECKED_IN':
        return checkInTime != null
            ? 'Checked In: $checkInTime'
            : 'Checked In Today';
      case 'COMPLETED':
        return checkOutTime != null
            ? 'Completed (Out: $checkOutTime)'
            : 'Attendance Complete';
      case 'NOT_CHECKED_IN':
      default:
        return 'Not Checked In Today';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final employeeName = _badgeData?['name']?.toString() ?? authService.userName ?? 'Employee';
    final employeeEmail = _badgeData?['email']?.toString() ?? authService.userEmail ?? '';
    final employeeCode = _badgeData?['staffId'] != null ? 'EMP-${_badgeData!['staffId']}' : 'WP-BADGE';
    final employeeRole = _badgeData?['role']?.toString() ?? 'Team Member';
    final todayStatus = _badgeData?['todayStatus']?.toString() ?? 'NOT_CHECKED_IN';
    final checkInTime = _badgeData?['checkInTime']?.toString();
    final checkOutTime = _badgeData?['checkOutTime']?.toString();

    final statusColor = _getStatusColor(todayStatus);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'My Attendance Badge',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Badge',
            onPressed: () {
              HapticFeedback.selectionClick();
              _fetchBadge();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _fetchBadge(),
        color: const Color(0xFF6366F1),
        backgroundColor: const Color(0xFF1E293B),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Main Digital Badge Card
              Container(
                width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Badge Header Ribbon
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF06B6D4)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(26),
                            topRight: Radius.circular(26),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.verified_user_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'WORKPULSE SMART BADGE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                employeeCode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            // Employee Profile Row
                            Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white24, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      employeeName.isNotEmpty
                                          ? employeeName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                                          : 'WP',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        employeeName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        employeeEmail,
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        employeeRole,
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),
                            const Divider(color: Color(0xFF334155), height: 1),
                            const SizedBox(height: 20),

                            // Dynamic QR Container
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 200,
                                      height: 200,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF4F46E5),
                                        ),
                                      ),
                                    )
                                  : _qrPayload != null && _qrPayload!.isNotEmpty
                                      ? QrImageView(
                                          data: _qrPayload!,
                                          version: QrVersions.auto,
                                          size: 200.0,
                                          eyeStyle: const QrEyeStyle(
                                            eyeShape: QrEyeShape.square,
                                            color: Color(0xFF0F172A),
                                          ),
                                          dataModuleStyle: const QrDataModuleStyle(
                                            dataModuleShape: QrDataModuleShape.square,
                                            color: Color(0xFF0F172A),
                                          ),
                                        )
                                      : SizedBox(
                                          width: 200,
                                          height: 200,
                                          child: Center(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.error_outline_rounded,
                                                    color: Color(0xFFEF4444),
                                                    size: 36,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    _errorMessage ?? 'Badge unavailable',
                                                    textAlign: TextAlign.center,
                                                    maxLines: 4,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFFEF4444),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  InkWell(
                                                    onTap: () {
                                                      HapticFeedback.selectionClick();
                                                      _fetchBadge();
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0F172A),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.refresh_rounded, size: 14, color: Colors.white),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Retry',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                            ),

                            const SizedBox(height: 18),

                            // Rotation Progress & Live Indicator
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ScaleTransition(
                                  scale: _pulseAnimation,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF10B981),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Rotates in ${_remainingSeconds}s',
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: (_remainingSeconds / 5.0).clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: const Color(0xFF334155),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _remainingSeconds > 2
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFFF59E0B),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Today's Status Pill
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    todayStatus == 'CHECKED_IN'
                                        ? Icons.login_rounded
                                        : todayStatus == 'COMPLETED'
                                            ? Icons.check_circle_rounded
                                            : Icons.access_time_rounded,
                                    color: statusColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _getStatusText(todayStatus, checkInTime, checkOutTime),
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Scanning Instructions Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'How to Check In / Check Out:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildInstructionRow('1', 'Hold this QR badge ~15-20 cm in front of the office kiosk tablet camera.'),
                    const SizedBox(height: 6),
                    _buildInstructionRow('2', 'The kiosk will beep and automatically log your attendance in <100ms.'),
                    const SizedBox(height: 6),
                    _buildInstructionRow('3', 'For maximum security, codes auto-rotate every 5s. Screenshots will be rejected.'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
