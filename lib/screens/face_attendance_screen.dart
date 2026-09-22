import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../utils/ist_helper.dart';
import 'native_face_scanner_screen.dart';

class FaceAttendanceScreen extends StatefulWidget {
  const FaceAttendanceScreen({super.key});

  @override
  State<FaceAttendanceScreen> createState() => _FaceAttendanceScreenState();
}

class _FaceAttendanceScreenState extends State<FaceAttendanceScreen> with WidgetsBindingObserver {
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    super.dispose();
  }

  void _launchAttendanceScanner() {
    // Open native ML Kit face scanner
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => const NativeFaceScannerScreen(),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 22),
            SizedBox(width: 10),
            Text(
              'Exit Kiosk Terminal',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out and exit the common attendance terminal?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Color(0xFF94A3B8),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit Kiosk', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      Provider.of<AuthService>(context, listen: false).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final terminalName = authService.userName ?? 'WorkPulse Terminal';
    final terminalEmail = authService.userEmail ?? 'attendance-kiosk@workpulse.com';

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF0F1D3E),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Color(0xFF10B981),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'QR Attendance Terminal',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                SizedBox(width: 5),
                Text(
                  'ONLINE',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF10B981),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
            tooltip: 'Exit Terminal',
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Live Clock & Date Banner
            _buildLiveClockBanner(),
            const SizedBox(height: 18),

            // Hero Scanner Launch Card
            _buildHeroScannerCard(),
            const SizedBox(height: 18),

            // Kiosk Highlights & Information
            _buildKioskFeatureGrid(),
            const SizedBox(height: 18),

            // Instructions for All Employees
            _buildEmployeeInstructionsCard(),
            const SizedBox(height: 18),

            // Terminal Details Card
            _buildTerminalDetailsCard(terminalName, terminalEmail),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveClockBanner() {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_currentTime);
    final timeStr = ISTHelper.formatTime(_currentTime);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF132247),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A8A).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: Color(0xFF93C5FD),
              ),
              const SizedBox(width: 8),
              Text(
                dateStr,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(
                Icons.access_time_filled_rounded,
                size: 16,
                color: Color(0xFF38BDF8),
              ),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroScannerCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated / Glowing Camera Ring
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Staff QR Attendance',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),

          const Text(
            'Common attendance terminal for all employees.\nHold employee Smart Badge in front of camera to record Check-In & Check-Out.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Color(0xFF94A3B8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),

          // Start QR Scanner Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _launchAttendanceScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF2563EB).withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Launch QR Scanner',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKioskFeatureGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildFeatureCard(
            icon: Icons.qr_code_2_rounded,
            iconColor: const Color(0xFF38BDF8),
            title: 'Dynamic QR Badge',
            subtitle: 'Single-use secure badge on phones',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildFeatureCard(
            icon: Icons.bolt_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Instant Scan',
            subtitle: 'Sub-second Check-In & Out',
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF132247),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E3A8A).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Color(0xFF94A3B8),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF132247),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E3A8A).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text(
                'How to Mark Attendance with QR',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStepRow(
            step: '1',
            title: 'Open WorkPulse App',
            description: 'Open the WorkPulse mobile app on your smartphone.',
          ),
          const SizedBox(height: 10),
          _buildStepRow(
            step: '2',
            title: 'Open Badge Tab',
            description: 'Tap the "Badge" tab at the bottom to view your active dynamic QR badge.',
          ),
          const SizedBox(height: 10),
          _buildStepRow(
            step: '3',
            title: 'Hold Up to Terminal Camera',
            description: 'Present your QR code 15-20 cm facing this terminal camera.',
          ),
          const SizedBox(height: 10),
          _buildStepRow(
            step: '4',
            title: 'Instant Confirmation',
            description: 'A chime sound and green celebration screen confirm your record.',
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String step,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF38BDF8),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalDetailsCard(String terminalName, String terminalEmail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.devices_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  terminalName,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE2E8F0),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  terminalEmail,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Text(
              'Terminal',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
