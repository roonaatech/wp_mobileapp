import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';

class MyAttendanceBadgeScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  const MyAttendanceBadgeScreen({super.key, this.onBackToHome});

  @override
  State<MyAttendanceBadgeScreen> createState() => _MyAttendanceBadgeScreenState();
}

class _MyAttendanceBadgeScreenState extends State<MyAttendanceBadgeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _badgeData;
  String? _qrPayload;
  int _remainingSeconds = 5;
  Timer? _countdownTimer;
  Timer? _rotationTimer;

  // WFH Attendance State
  bool _isWfhDay = false;
  String _workMode = 'Office';
  String? _todayDayOfWeek;
  double? _latitude;
  double? _longitude;
  String? _gpsError;
  bool _isPunching = false;
  final TextEditingController _notesController = TextEditingController();
  Timer? _elapsedTimer;
  String _elapsedTime = '';

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchBadge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _rotationTimer?.cancel();
    _elapsedTimer?.cancel();
    _notesController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When user returns to the app from settings, re-attempt GPS acquisition automatically
      if (_isWfhDay && (_latitude == null || _longitude == null)) {
        _captureLocation(promptUser: false);
      }
    }
  }

  Future<void> _promptEnableLocationService() async {
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: Color(0xFFF59E0B), size: 24),
            SizedBox(width: 10),
            Text(
              'Location Required',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Work From Home attendance (check-in and check-out) strictly requires location services to be enabled on your device to verify your remote attendance location.\n\nPlease turn on Location in your device settings to proceed.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Open Location Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await Geolocator.openLocationSettings();
    }
  }

  Future<void> _promptOpenAppSettings() async {
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 10),
            Text(
              'Permission Required',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'WorkPulse requires location permission to capture your remote attendance coordinates for check-in and check-out.\n\nPlease grant Location permission in App Settings.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Open App Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await Geolocator.openAppSettings();
    }
  }

  Future<bool> _captureLocation({bool promptUser = false}) async {
    if (!mounted) return false;
    setState(() {
      _gpsError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _latitude = null;
            _longitude = null;
            _gpsError = 'Location services disabled. Please enable GPS in device settings.';
          });
        }
        if (promptUser) {
          await _promptEnableLocationService();
        }
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _latitude = null;
              _longitude = null;
              _gpsError = 'Location permission denied. Cannot capture attendance coordinates.';
            });
          }
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _latitude = null;
            _longitude = null;
            _gpsError = 'Location permissions permanently denied. Please enable in app settings.';
          });
        }
        if (promptUser) {
          await _promptOpenAppSettings();
        }
        return false;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return false;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsError = null;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _latitude = null;
        _longitude = null;
        _gpsError = 'Could not acquire GPS: ${e.toString().replaceAll('Exception: ', '')}';
      });
      return false;
    }
  }

  void _startElapsedTimer(String? checkInTimeStr) {
    _elapsedTimer?.cancel();
    if (checkInTimeStr == null || checkInTimeStr.isEmpty) {
      setState(() => _elapsedTime = '');
      return;
    }

    void updateElapsed() {
      DateTime? startTime;
      try {
        startTime = DateTime.tryParse(checkInTimeStr);
      } catch (_) {}

      if (startTime != null && startTime.isUtc) {
        final nowUtc = DateTime.now().toUtc();
        var diff = nowUtc.difference(startTime);
        if (diff.isNegative) diff = Duration.zero;
        final hrs = diff.inHours.toString().padLeft(2, '0');
        final mins = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() {
            _elapsedTime = '$hrs:$mins:$secs';
          });
        }
        return;
      }

      final now = DateTime.now();
      if (startTime == null) {
        final parts = checkInTimeStr.split(' ');
        if (parts.length >= 2) {
          try {
            final timeParts = parts[0].split(':');
            int hour = int.parse(timeParts[0]);
            final minute = int.parse(timeParts[1]);
            final isPm = parts[1].toUpperCase() == 'PM';
            if (isPm && hour < 12) hour += 12;
            if (!isPm && hour == 12) hour = 0;
            startTime = DateTime(now.year, now.month, now.day, hour, minute);
          } catch (_) {}
        }
      }

      if (startTime != null) {
        var diff = DateTime.now().difference(startTime);
        if (diff.isNegative) diff = Duration.zero;
        final hrs = diff.inHours.toString().padLeft(2, '0');
        final mins = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final secs = (diff.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() {
            _elapsedTime = '$hrs:$mins:$secs';
          });
        }
      }
    }

    updateElapsed();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) => updateElapsed());
  }

  Future<void> _handleWfhPunch(String action) async {
    if (!mounted) return;
    setState(() => _isPunching = true);

    try {
      // STRICT LOCATION ENFORCEMENT: Ensure location service is active and GPS captured for BOTH check-in and check-out
      final captured = await _captureLocation(promptUser: true);
      if (!captured || _latitude == null || _longitude == null || (_latitude == 0 && _longitude == 0)) {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        final actionVerb = action == 'CHECK_IN' ? 'check in' : 'check out';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _gpsError ?? 'Location required: Please enable device location in settings to $actionVerb.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => _captureLocation(promptUser: true),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        return; // Strictly abort check-in or check-out without location
      }

      if (!mounted) return;
      final service = Provider.of<AttendanceService>(context, listen: false);
      final res = await service.wfhPunch(
        action: action,
        latitude: _latitude,
        longitude: _longitude,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Punch recorded successfully!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      _notesController.clear();

      // Immediately and optimistically update state so Checkout button appears with zero delay
      final nextStatus = res['todayStatus']?.toString() ?? (action == 'CHECK_IN' ? 'CHECKED_IN' : 'COMPLETED');
      final timeStr = res['time']?.toString() ?? res['timestamp']?.toString();
      final isoStr = res['checkInIso']?.toString() ?? res['log']?['check_in_time']?.toString();

      setState(() {
        _badgeData = {
          ...?_badgeData,
          'todayStatus': nextStatus,
          if (action == 'CHECK_IN') ...{
            'checkInTime': timeStr,
            'checkInIso': isoStr,
          } else ...{
            'checkOutTime': timeStr,
          },
        };
      });

      if (action == 'CHECK_IN') {
        _startElapsedTimer(isoStr ?? timeStr);
      } else {
        _elapsedTimer?.cancel();
        setState(() => _elapsedTime = '');
      }

      // Re-fetch badge silently to ensure server synchronization
      await _fetchBadge(silent: true);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPunching = false);
    }
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

        final String mode = response['workMode']?.toString() ?? badge['workMode']?.toString() ?? 'Office';
        final bool isWfh = response['isWfhDay'] == true || badge['isWfhDay'] == true;
        final String? dow = response['todayDayOfWeek']?.toString() ?? badge['todayDayOfWeek']?.toString();

        final qr = isWfh
            ? ''
            : (response['qrPayload']?.toString() ?? badge['qrPayload']?.toString() ?? '');

        final dynamic ttlVal = response['ttlSeconds'] ?? badge['ttlSeconds'] ?? 5;
        final int ttl = (ttlVal is num) ? ttlVal.toInt() : int.tryParse(ttlVal.toString()) ?? 5;

        final todayStatus = response['todayStatus'] ?? badge['todayStatus'] ?? 'NOT_CHECKED_IN';
        final checkInTime = response['checkInTime'] ?? badge['checkInTime'];
        final checkOutTime = response['checkOutTime'] ?? badge['checkOutTime'];
        final checkInIso = response['checkInIso'] ?? badge['checkInIso'];

        final badgeData = <String, dynamic>{
          'staffId': emp['staffId'] ?? badge['staffId'] ?? response['staffId'],
          'name': emp['name'] ?? badge['name'] ?? response['name'],
          'email': emp['email'] ?? badge['email'] ?? response['email'],
          'role': emp['role'] ?? badge['role'] ?? response['role'],
          'department': emp['department'] ?? badge['department'] ?? response['department'],
          'avatarUrl': emp['avatarUrl'] ?? badge['avatarUrl'] ?? response['avatarUrl'],
          'todayStatus': todayStatus,
          'checkInTime': checkInTime,
          'checkOutTime': checkOutTime,
          'checkInIso': checkInIso,
          'qrPayload': qr,
          'expiresAt': response['expiresAt'] ?? badge['expiresAt'],
          'ttlSeconds': ttl,
          'isWfhDay': isWfh,
          'workMode': mode,
          'todayDayOfWeek': dow,
        };

        final List<String>? days = response['hybridOfficeDays'] is List
            ? (response['hybridOfficeDays'] as List).map((e) => e.toString()).toList()
            : (badge['hybridOfficeDays'] is List
                ? (badge['hybridOfficeDays'] as List).map((e) => e.toString()).toList()
                : null);

        try {
          final auth = Provider.of<AuthService>(context, listen: false);
          auth.updateWorkMode(mode, days);
        } catch (_) {}

        setState(() {
          _badgeData = badgeData;
          _qrPayload = qr;
          _isWfhDay = isWfh;
          _workMode = mode;
          _todayDayOfWeek = dow;
          if (!silent) {
            _remainingSeconds = ttl > 0 ? ttl : 5;
          }
          _isLoading = false;
          _errorMessage = null;
        });

        if (isWfh) {
          // On WFH days, disable QR countdown timer
          _countdownTimer?.cancel();
          // Automatically capture GPS location
          _captureLocation();
          // If already checked in, start elapsed timer
          if (todayStatus == 'CHECKED_IN') {
            _startElapsedTimer(checkInIso?.toString() ?? checkInTime?.toString());
          }
        } else {
          // Office day: Start 5s QR auto-rotation
          _startCountdown();
        }
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
        return const Color(0xFF38BDF8);
      case 'ON_LEAVE':
        return const Color(0xFFA855F7);
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
      case 'ON_LEAVE':
        return 'On Approved Leave Today';
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
    final bool isViewingWfh = _isWfhDay;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.onBackToHome != null) {
              widget.onBackToHome!();
            }
          },
        ),
        title: Text(
          isViewingWfh ? (_workMode == 'Hybrid' ? 'Hybrid Attendance' : 'WFH Attendance') : 'My Attendance Badge',
          style: const TextStyle(
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
            tooltip: 'Refresh',
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
              // Main Card Container
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
                    color: isViewingWfh
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.45)
                        : const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isViewingWfh ? const Color(0xFF38BDF8) : const Color(0xFF10B981)).withValues(alpha: 0.12),
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
                    // Header Ribbon
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isViewingWfh
                              ? [const Color(0xFF2563EB), const Color(0xFF0284C7)]
                              : [const Color(0xFF059669), const Color(0xFF0D9488)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(26),
                          topRight: Radius.circular(26),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isViewingWfh ? const Color(0xFF2563EB) : const Color(0xFF059669)).withValues(alpha: 0.3),
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
                            child: Icon(
                              isViewingWfh ? Icons.home_work_rounded : Icons.verified_user_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _workMode == 'Hybrid'
                                  ? (isViewingWfh
                                      ? (_todayDayOfWeek != null ? 'HYBRID WFH ($_todayDayOfWeek)' : 'HYBRID WFH ATTENDANCE')
                                      : (_todayDayOfWeek != null ? 'HYBRID IN-OFFICE ($_todayDayOfWeek)' : 'HYBRID IN-OFFICE BADGE'))
                                  : (_isWfhDay ? 'WORK FROM HOME ATTENDANCE' : 'WORKPULSE SMART BADGE'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                                  gradient: LinearGradient(
                                    colors: _isWfhDay
                                        ? [const Color(0xFF38BDF8), const Color(0xFF2563EB)]
                                        : [const Color(0xFF10B981), const Color(0xFF059669)],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isWfhDay ? const Color(0xFF38BDF8) : const Color(0xFF10B981)).withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    employeeName.isNotEmpty ? employeeName[0].toUpperCase() : 'E',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
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
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      employeeRole,
                                      style: TextStyle(
                                        color: _isWfhDay ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (employeeEmail.isNotEmpty)
                                      Text(
                                        employeeEmail,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 10,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),
                          const Divider(color: Color(0xFF334155), height: 1),
                          const SizedBox(height: 16),

                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusText(todayStatus, checkInTime, checkOutTime),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // =========================================================
                          // CONDITIONAL: WFH PUNCH vs IN-OFFICE QR BADGE
                          // =========================================================
                          if (isViewingWfh) ...[
                            // ─── WFH PUNCH UI (DO NOT SHOW QR CODE) ───

                            // Live Elapsed Stopwatch if checked in
                            if (todayStatus == 'CHECKED_IN' && _elapsedTime.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF047857), Color(0xFF0D9488)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'SESSION DURATION',
                                      style: TextStyle(
                                        color: Color(0xFFA7F3D0),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _elapsedTime,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    if (checkInTime != null)
                                      Text(
                                        'In at $checkInTime',
                                        style: const TextStyle(
                                          color: Color(0xFFD1FAE5),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Work Notes / Summary Text Field
                            if (todayStatus != 'COMPLETED' && todayStatus != 'ON_LEAVE') ...[
                              TextField(
                                controller: _notesController,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: todayStatus == 'CHECKED_IN'
                                      ? 'Optional checkout notes / summary...'
                                      : 'Optional: What are you working on today?...',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFF334155)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFF334155)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                                  ),
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Action Button: Clean Check In / Check Out
                            if (todayStatus == 'NOT_CHECKED_IN')
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isPunching ? null : () => _handleWfhPunch('CHECK_IN'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 8,
                                    shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                                  ),
                                  child: _isPunching
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.login_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Check In',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              )
                            else if (todayStatus == 'CHECKED_IN')
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isPunching ? null : () => _handleWfhPunch('CHECK_OUT'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 8,
                                    shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                  ),
                                  child: _isPunching
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.logout_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Check Out',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              )
                            else if (todayStatus == 'COMPLETED')
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Attendance Complete for Today',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline_rounded, color: Color(0xFFA855F7), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'You are on Approved Leave Today',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 14),
                            // Security info
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_rounded, color: Color(0xFF38BDF8), size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Bound Device & GPS coordinates logged securely',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            // ─── OFFICE DYNAMIC QR CODE VIEW (OFFICE DAYS ONLY) ───
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
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Anti-Replay',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Instructions / Help card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF334155),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _isWfhDay ? 'WFH Attendance Instructions:' : 'How to Check In / Check Out:',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_isWfhDay) ...[
                      _buildInstructionRow('1', 'Tap Check-In when you begin work. GPS coordinates are recorded automatically.'),
                      const SizedBox(height: 6),
                      _buildInstructionRow('2', 'Add an optional work note or task summary when checking out.'),
                      const SizedBox(height: 6),
                      _buildInstructionRow('3', 'Checkout logs are automatically routed to your reporting manager for confirmation.'),
                    ] else ...[
                      _buildInstructionRow('1', 'Hold this QR badge ~15-20 cm in front of the office kiosk tablet camera.'),
                      const SizedBox(height: 6),
                      _buildInstructionRow('2', 'The kiosk will beep and automatically log your attendance in <100ms.'),
                      const SizedBox(height: 6),
                      _buildInstructionRow('3', 'For maximum security, codes auto-rotate every 5s. Screenshots will be rejected.'),
                    ],
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
