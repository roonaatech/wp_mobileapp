import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/attendance_service.dart';
import '../utils/camera_face_frame.dart';
import '../utils/ist_helper.dart';

/// QR Badge Attendance Terminal - the mobile counterpart of the web portal's
/// QR Attendance Terminal (wp_webapp/src/pages/Attendance.jsx):
///
/// 1. Continuously scans video frames using Google ML Kit Barcode Scanning.
/// 2. Decodes dynamic 'WPQR.' badges generated on employee smartphones.
/// 3. Records attendance via `/api/attendance/scan-qr-badge` with location & device info.
/// 4. Plays audio / haptic confirmation and shows celebration dialog with auto-reset countdown.
class NativeFaceScannerScreen extends StatefulWidget {
  const NativeFaceScannerScreen({super.key});

  @override
  State<NativeFaceScannerScreen> createState() => _NativeFaceScannerScreenState();
}

typedef QrAttendanceScannerScreen = NativeFaceScannerScreen;

class _NativeFaceScannerScreenState extends State<NativeFaceScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  bool _isDisposed = false;
  bool _isFlashOn = false;

  late final BarcodeScanner _barcodeScanner;
  late AnimationController _scanAnimController;
  late Animation<double> _scanAnimation;

  // Frame processing loop
  bool _processingFrame = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _frameInterval = Duration(milliseconds: 100);

  bool _isProcessingQr = false;
  bool _isRecordingAttendance = false;
  String? _lastScannedPayload;
  DateTime _lastQrScanTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _statusMessage = 'Hold Smart Badge in front of camera';

  String? _accessDeniedMessage;
  Timer? _accessDeniedTimer;

  final ValueNotifier<int> _resetCountdownNotifier = ValueNotifier<int>(4);
  Timer? _autoResetTimer;

  bool get _isActive => mounted && !_isDisposed;
  bool get _canProcessFrames => _isActive && !_isRecordingAttendance && _accessDeniedMessage == null && !_isProcessingQr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnimController, curve: Curves.easeInOut),
    );

    _requestCameraPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_selectedCameraIndex);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _scanAnimController.dispose();
    _accessDeniedTimer?.cancel();
    _autoResetTimer?.cancel();
    _resetCountdownNotifier.dispose();
    _barcodeScanner.close();
    _releaseCamera();
    super.dispose();
  }

  // ----------------------------------------------------------- camera setup

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (!_isActive) return;
      setState(() {
        _isPermissionDenied = false;
      });
      await _setupCameras();
    } else {
      if (!_isActive) return;
      setState(() {
        _isPermissionDenied = true;
      });
    }
  }

  Future<void> _setupCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final frontCameraIndex = _cameras.indexWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );

      _selectedCameraIndex = frontCameraIndex != -1 ? frontCameraIndex : 0;
      await _initCamera(_selectedCameraIndex);
    } catch (_) {}
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (_cameras.isEmpty || _isDisposed) return;

    final controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );

    try {
      await controller.initialize();
      if (!_isActive) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      _selectedCameraIndex = cameraIndex;
      _isFlashOn = false;
      await controller.startImageStream(_onCameraImage);
      if (!_isActive) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
      if (identical(_cameraController, controller)) _cameraController = null;
      await controller.dispose();
      if (_isActive) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  void _releaseCamera() {
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) return;
    () async {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      await controller.dispose();
    }();
  }

  void _disposeCamera() {
    _releaseCamera();
    if (_isActive) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  void _toggleCamera() {
    if (_cameras.length <= 1 || _isDisposed) return;
    final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _disposeCamera();
    _initCamera(nextIndex);
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final newFlash = !_isFlashOn;
      await _cameraController!.setFlashMode(newFlash ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() {
          _isFlashOn = newFlash;
        });
      }
    } catch (_) {}
  }

  // ----------------------------------------------------------- frame loop

  void _onCameraImage(CameraImage image) {
    if (_processingFrame || !_canProcessFrames) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < _frameInterval) return;
    _lastFrameAt = now;
    _processingFrame = true;
    _processFrame(image).whenComplete(() => _processingFrame = false);
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    final controller = _cameraController;
    if (controller == null || _isProcessingQr || _isRecordingAttendance) return;

    try {
      final frame = CameraFaceFrame.fromCameraImage(
        cameraImage,
        controller.description,
        controller.value.deviceOrientation,
      );
      if (frame == null) return;

      final barcodes = await _barcodeScanner.processImage(frame.inputImage);
      if (!_canProcessFrames || _isProcessingQr) return;

      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw != null && raw.startsWith('WPQR.')) {
          await _handleQrAttendance(raw);
          break;
        }
      }
    } catch (e) {
      debugPrint('QR barcode frame processing error: $e');
    }
  }

  // ----------------------------------------------------------- attendance

  Future<void> _handleQrAttendance(String qrPayload) async {
    if (_isProcessingQr || _isRecordingAttendance) return;
    final now = DateTime.now();
    if (_lastScannedPayload == qrPayload && now.difference(_lastQrScanTime).inSeconds < 3) {
      return;
    }
    _lastScannedPayload = qrPayload;
    _lastQrScanTime = now;
    _isProcessingQr = true;

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    setState(() {
      _isRecordingAttendance = true;
      _statusMessage = 'Verifying Smart Badge...';
    });

    try {
      final attendanceService = Provider.of<AttendanceService>(context, listen: false);
      final position = await _currentPosition();
      final phoneModel = await _phoneModel();

      final result = await attendanceService.scanQrBadgeAttendance(
        qrPayload: qrPayload,
        latitude: position?.latitude,
        longitude: position?.longitude,
        phoneModel: phoneModel,
      );

      if (!_isActive) return;

      final recordedAction = result['type']?.toString() ?? 'CHECK_IN';
      final employeeName = result['employeeName']?.toString() ?? 'Employee';
      final timestamp = result['timestamp'] != null
          ? ISTHelper.formatTime(DateTime.tryParse(result['timestamp'].toString()) ?? DateTime.now())
          : ISTHelper.formatTime(DateTime.now());
      final duration = result['duration']?.toString();

      HapticFeedback.heavyImpact();

      setState(() {
        _isRecordingAttendance = false;
        _statusMessage = '${recordedAction == 'CHECK_IN' ? 'Check-In' : 'Check-Out'} logged!';
      });

      await _showCelebrationDialog(
        action: recordedAction,
        employeeName: employeeName,
        timestamp: timestamp,
        duration: duration,
      );
    } catch (e) {
      if (!_isActive) return;
      HapticFeedback.vibrate();
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isRecordingAttendance = false;
        _accessDeniedMessage = message;
        _statusMessage = 'Badge verification failed';
      });
      _accessDeniedTimer?.cancel();
      _accessDeniedTimer = Timer(const Duration(seconds: 3), () {
        if (_isActive) {
          setState(() {
            _accessDeniedMessage = null;
            _statusMessage = 'Hold Smart Badge in front of camera';
          });
        }
      });
    } finally {
      _isProcessingQr = false;
    }
  }

  Future<Position?> _currentPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<String> _phoneModel() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.utsname.machine;
      }
    } catch (_) {}
    return 'WorkPulse Mobile Kiosk';
  }

  Future<void> _showCelebrationDialog({
    required String action,
    required String employeeName,
    required String timestamp,
    String? duration,
  }) async {
    final isCheckIn = action == 'CHECK_IN';

    // Auto-close countdown timer (4 seconds) for zero-touch shared kiosk operation
    _resetCountdownNotifier.value = 4;
    _autoResetTimer?.cancel();
    _autoResetTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resetCountdownNotifier.value > 1) {
        _resetCountdownNotifier.value--;
      } else {
        timer.cancel();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isCheckIn ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isCheckIn ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isCheckIn ? const Color(0xFF10B981) : const Color(0xFF38BDF8)).withValues(alpha: 0.2),
                  border: Border.all(
                    color: isCheckIn ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isCheckIn ? Icons.check_circle_rounded : Icons.logout_rounded,
                  color: isCheckIn ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                isCheckIn ? 'Check-In Successful!' : 'Check-Out Successful!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                'Welcome, $employeeName',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                ),
              ),
              const SizedBox(height: 16),

              // Timestamp & Details Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'TIME',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timestamp,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (duration != null && duration.isNotEmpty) ...[
                      Container(width: 1, height: 28, color: const Color(0xFF334155)),
                      Column(
                        children: [
                          const Text(
                            'SHIFT HOURS',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            duration,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Auto-close countdown
              ValueListenableBuilder<int>(
                valueListenable: _resetCountdownNotifier,
                builder: (context, seconds, _) {
                  return Text(
                    'Ready for next scan in ${seconds}s...',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Done Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCheckIn ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _statusMessage = 'Hold Smart Badge in front of camera';
      });
    }
  }

  // ----------------------------------------------------------- UI building

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Camera Viewport Stream
            if (_isPermissionDenied)
              _buildPermissionDeniedView()
            else if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized)
              _buildCameraLoadingView()
            else
              _buildCameraPreviewView(),

            // 2. Top Bar (Exit, Live Pill, Flip Camera, Flashlight)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildTopControlBar(),
            ),

            // 3. Central scanning guide (QR Badge Viewfinder)
            if (_isCameraInitialized && !_isPermissionDenied)
              Center(
                child: _buildQrScanningGuide(),
              ),

            // 4. Bottom identification / attendance panel
            if (!_isPermissionDenied)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomPanel(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControlBar() {
    final String pillText;
    final Color pillColor;
    if (_isRecordingAttendance) {
      pillText = 'RECORDING BADGE';
      pillColor = const Color(0xFF10B981);
    } else {
      pillText = 'READY TO SCAN';
      pillColor = const Color(0xFF38BDF8);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Exit Button
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Exit',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Live Scanner Status Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pillColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: pillColor),
              const SizedBox(width: 6),
              Text(
                pillText,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: pillColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        // Right controls: Flashlight & Flip Camera
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flashlight Toggle
            InkWell(
              onTap: _toggleFlash,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: _isFlashOn ? const Color(0xFFFBBF24) : const Color(0xFF334155)),
                ),
                child: Icon(
                  _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _isFlashOn ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Flip Camera Toggle
            if (_cameras.length > 1)
              InkWell(
                onTap: _toggleCamera,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios_rounded,
                    color: Color(0xFF38BDF8),
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraPreviewView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return _buildCameraLoadingView();
    }

    return Positioned.fill(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _cameraController!.value.previewSize?.height ?? 1,
              height: _cameraController!.value.previewSize?.width ?? 1,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrScanningGuide() {
    final size = MediaQuery.of(context).size;
    final boxSize = (size.width * 0.72).clamp(240.0, 320.0);

    final Color ringColor = _accessDeniedMessage != null
        ? const Color(0xFFEF4444)
        : _isRecordingAttendance
            ? const Color(0xFF10B981)
            : const Color(0xFF38BDF8);

    return SizedBox(
      width: boxSize + 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: ringColor.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // 4 Corner Accents
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: ringColor, width: 4.5),
                        left: BorderSide(color: ringColor, width: 4.5),
                      ),
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(20)),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: ringColor, width: 4.5),
                        right: BorderSide(color: ringColor, width: 4.5),
                      ),
                      borderRadius: const BorderRadius.only(topRight: Radius.circular(20)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: ringColor, width: 4.5),
                        left: BorderSide(color: ringColor, width: 4.5),
                      ),
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: ringColor, width: 4.5),
                        right: BorderSide(color: ringColor, width: 4.5),
                      ),
                      borderRadius: const BorderRadius.only(bottomRight: Radius.circular(20)),
                    ),
                  ),
                ),

                // Center crosshair
                Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(color: ringColor.withValues(alpha: 0.4), width: 1.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Animated Laser Line
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: _scanAnimation.value * (boxSize - 16),
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              ringColor.withValues(alpha: 0.1),
                              ringColor,
                              ringColor.withValues(alpha: 0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ringColor,
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _accessDeniedMessage != null ? Icons.error_outline_rounded : Icons.qr_code_scanner_rounded,
                  color: ringColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _accessDeniedMessage ?? _statusMessage,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border.all(color: const Color(0xFF1E3A8A).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          _buildQrScanningContent(),
        ],
      ),
    );
  }

  Widget _buildQrScanningContent() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF818CF8), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart Badge Terminal',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Present your phone badge 15-20 cm from camera',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 16),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Dynamic single-use security badge. Auto-verifies and returns in 4 seconds.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraLoadingView() {
    return Container(
      color: const Color(0xFF0B132B),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Initializing Camera Hardware...',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Container(
      color: const Color(0xFF0B132B),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, size: 64, color: Color(0xFFF87171)),
            const SizedBox(height: 16),
            const Text(
              'Camera Permission Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'WorkPulse requires camera permission to scan employee QR badges for attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _requestCameraPermission,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Grant Camera Access', style: TextStyle(fontFamily: 'Poppins')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
