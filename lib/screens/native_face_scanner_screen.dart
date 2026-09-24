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

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraDescription? get _currentCamera =>
      (_cameras.isNotEmpty && _selectedCameraIndex < _cameras.length)
          ? _cameras[_selectedCameraIndex]
          : null;

  bool get _isBackCamera =>
      _currentCamera?.lensDirection == CameraLensDirection.back;

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

      // Prefer BACK camera for handheld QR scanning; fallback to front or 0
      final backCameraIndex = _cameras.indexWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
      );
      final frontCameraIndex = _cameras.indexWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );

      _selectedCameraIndex = backCameraIndex != -1
          ? backCameraIndex
          : (frontCameraIndex != -1 ? frontCameraIndex : 0);

      await _initCamera(_selectedCameraIndex);
    } catch (_) {}
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (_cameras.isEmpty || _isDisposed) return;

    CameraController controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.medium, // 480p: optimal resolution for instant ML Kit QR detection with minimal NV21 conversion overhead (<10ms)
      enableAudio: false,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );

    try {
      try {
        await controller.initialize();
      } catch (_) {
        // Fallback to high resolution preset if medium is not supported on device
        controller = CameraController(
          _cameras[cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
        );
        await controller.initialize();
      }

      if (!_isActive) {
        await controller.dispose();
        return;
      }
      _cameraController = controller;
      _selectedCameraIndex = cameraIndex;
      _isFlashOn = false;

      // Attempt continuous auto-focus for sharp QR detection
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

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

  Future<void> _onTapFocus(TapDownDetails details, BoxConstraints constraints) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final point = Offset(
        (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
        (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
      );
      await controller.setFocusPoint(point);
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
  }

  // ----------------------------------------------------------- frame loop

  void _onCameraImage(CameraImage image) {
    if (_processingFrame || !_canProcessFrames) return;
    _processingFrame = true;
    _processFrame(image).whenComplete(() => _processingFrame = false);
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null || _cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return null;
    }
    final camera = _cameras[_selectedCameraIndex];

    // 1. Calculate rotation compensation
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (camera.sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (camera.sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // 2. iOS format: BGRA8888
    if (Platform.isIOS) {
      if (image.planes.isEmpty) return null;
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // 3. Android format: NV21 or YUV_420_888
    if (Platform.isAndroid) {
      final int numPixels = image.width * image.height;
      final int expectedNv21Length = numPixels + (numPixels ~/ 2);

      // Case A: Stream already single-plane with complete NV21 buffer
      if (image.planes.length == 1 && image.planes.first.bytes.length >= expectedNv21Length) {
        final plane = image.planes.first;
        return InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: imageSize,
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      }

      // Case B: Multi-plane YUV_420_888 (standard Android stream) -> Convert to NV21
      if (image.planes.length >= 3) {
        final nv21Bytes = _convertYuv420ToNv21(image);
        return InputImage.fromBytes(
          bytes: nv21Bytes,
          metadata: InputImageMetadata(
            size: imageSize,
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      }

      // Case C: Single plane fallback
      if (image.planes.isNotEmpty) {
        final plane = image.planes.first;
        return InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: imageSize,
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      }
    }

    return null;
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final Uint8List yBuffer = yPlane.bytes;
    final Uint8List uBuffer = uPlane.bytes;
    final Uint8List vBuffer = vPlane.bytes;

    final int numPixels = width * height;
    final Uint8List nv21 = Uint8List(numPixels + (numPixels ~/ 2));

    // Copy Y channel
    if (yPlane.bytesPerRow == width) {
      nv21.setRange(0, numPixels, yBuffer);
    } else {
      int dstOffset = 0;
      for (int row = 0; row < height; row++) {
        final int srcOffset = row * yPlane.bytesPerRow;
        nv21.setRange(dstOffset, dstOffset + width, yBuffer, srcOffset);
        dstOffset += width;
      }
    }

    // Interleave V and U channels (NV21 format: Y... followed by V0 U0 V1 U1...)
    int uvDstIndex = numPixels;
    final int uRowStride = uPlane.bytesPerRow;
    final int vRowStride = vPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 1;
    final int vPixelStride = vPlane.bytesPerPixel ?? 1;

    final int chromaHeight = height ~/ 2;
    final int chromaWidth = width ~/ 2;

    for (int row = 0; row < chromaHeight; row++) {
      final int uRowStart = row * uRowStride;
      final int vRowStart = row * vRowStride;
      for (int col = 0; col < chromaWidth; col++) {
        final int vIndex = vRowStart + (col * vPixelStride);
        final int uIndex = uRowStart + (col * uPixelStride);

        if (vIndex < vBuffer.length && uIndex < uBuffer.length && uvDstIndex + 1 < nv21.length) {
          nv21[uvDstIndex++] = vBuffer[vIndex];
          nv21[uvDstIndex++] = uBuffer[uIndex];
        }
      }
    }

    return nv21;
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    final controller = _cameraController;
    if (controller == null || _isProcessingQr || _isRecordingAttendance) return;

    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) return;

      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!_canProcessFrames || _isProcessingQr) return;

      for (final barcode in barcodes) {
        final raw = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
        if (raw.isNotEmpty) {
          if (raw.startsWith('WPQR.')) {
            await _handleQrAttendance(raw);
            break;
          } else {
            _showInvalidQrWarning(raw);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('QR barcode frame processing error: $e');
    }
  }

  void _showInvalidQrWarning(String raw) {
    if (_accessDeniedMessage != null || _isRecordingAttendance) return;
    HapticFeedback.selectionClick();
    setState(() {
      _accessDeniedMessage = 'Invalid QR Code. Please show WorkPulse Dynamic Badge';
      _statusMessage = 'Unrecognized QR code';
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

      if (result['requiresConfirmation'] == true) {
        final confirmationToken = result['confirmationToken']?.toString();
        final action = result['type']?.toString() ?? 'CHECK_IN';
        final employeeName = result['employeeName']?.toString() ?? 'Employee';
        final timestamp = result['timestamp']?.toString() ?? '';
        final duration = result['duration']?.toString();

        setState(() {
          _isRecordingAttendance = false;
          _statusMessage = 'Confirmation required';
        });

        final confirmed = await _showConfirmationDialog(
          action: action,
          employeeName: employeeName,
          timestamp: timestamp,
          duration: duration,
        );

        if (!confirmed) {
          setState(() {
            _isRecordingAttendance = false;
            _statusMessage = '${action == 'CHECK_IN' ? 'Check-In' : 'Check-Out'} cancelled';
          });
          Timer(const Duration(seconds: 2), () {
            if (_isActive) {
              setState(() {
                _statusMessage = 'Hold Smart Badge in front of camera';
              });
            }
          });
          return;
        }

        // Confirmed by user -> execute attendance record
        setState(() {
          _isRecordingAttendance = true;
          _statusMessage = 'Recording ${action == 'CHECK_IN' ? 'Check-In' : 'Check-Out'}...';
        });

        final confirmResult = await attendanceService.scanQrBadgeAttendance(
          confirmationToken: confirmationToken,
          confirmed: true,
          latitude: position?.latitude,
          longitude: position?.longitude,
          phoneModel: phoneModel,
        );

        if (!_isActive) return;

        final recordedAction = confirmResult['type']?.toString() ?? action;
        final confEmployeeName = confirmResult['employeeName']?.toString() ?? employeeName;
        final confTimestamp = confirmResult['timestamp'] != null
            ? ISTHelper.formatTime(DateTime.tryParse(confirmResult['timestamp'].toString()) ?? DateTime.now())
            : ISTHelper.formatTime(DateTime.now());
        final confDuration = confirmResult['duration']?.toString() ?? duration;

        HapticFeedback.heavyImpact();

        setState(() {
          _isRecordingAttendance = false;
          _statusMessage = '${recordedAction == 'CHECK_IN' ? 'Check-In' : 'Check-Out'} logged!';
        });

        await _showCelebrationDialog(
          action: recordedAction,
          employeeName: confEmployeeName,
          timestamp: confTimestamp,
          duration: confDuration,
        );
        return;
      }

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

  Future<bool> _showConfirmationDialog({
    required String action,
    required String employeeName,
    required String timestamp,
    String? duration,
  }) async {
    final isCheckIn = action == 'CHECK_IN';
    final actionLabel = isCheckIn ? 'Check In' : 'Check Out';
    final accentColor = isCheckIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    final countdownNotifier = ValueNotifier<int>(15);
    Timer? dialogTimer;

    dialogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownNotifier.value > 1) {
        countdownNotifier.value--;
      } else {
        timer.cancel();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(false);
        }
      }
    });

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: accentColor,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Action Icon
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.15),
                  border: Border.all(
                    color: accentColor,
                    width: 2.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                    color: accentColor,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isCheckIn ? 'CHECK-IN CONFIRMATION' : 'CHECK-OUT CONFIRMATION',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Confirmation Question
              Text(
                'Confirm $actionLabel?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                employeeName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE2E8F0),
                ),
              ),
              const SizedBox(height: 16),

              // Details box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timestamp.isNotEmpty ? timestamp : ISTHelper.formatTime(DateTime.now()),
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
                            'DURATION',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
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
              const SizedBox(height: 16),

              // Auto-cancel countdown hint
              ValueListenableBuilder<int>(
                valueListenable: countdownNotifier,
                builder: (context, seconds, _) {
                  return Text(
                    'Auto-cancelling in ${seconds}s...',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              // Action Buttons: NO / YES
              Row(
                children: [
                  // NO Button
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF475569), width: 1.5),
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: const Color(0xFF94A3B8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        dialogTimer?.cancel();
                        Navigator.of(ctx).pop(false);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close_rounded, size: 18, color: Color(0xFFEF4444)),
                          SizedBox(width: 6),
                          Text(
                            'NO',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // YES Button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                        shadowColor: accentColor.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        dialogTimer?.cancel();
                        Navigator.of(ctx).pop(true);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded, size: 20, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'YES',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    dialogTimer.cancel();
    return confirmed == true;
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: Color(0xFF38BDF8),
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isBackCamera ? 'Back' : 'Front',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _onTapFocus(details, constraints),
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
        },
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Smart Badge Terminal',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _isBackCamera ? 'BACK CAM' : 'FRONT CAM',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Point camera at employee phone badge (15-25 cm)',
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
          child: const Row(
            children: [
              Icon(Icons.touch_app_rounded, color: Color(0xFF38BDF8), size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap screen to focus if needed. Dynamic badge auto-verifies instantly.',
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
