import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/attendance_service.dart';
import '../services/face_recognition_service.dart';
import '../utils/camera_face_frame.dart';
import '../utils/face_geometry.dart';
import '../utils/face_snapshot.dart';
import '../utils/ist_helper.dart';

// Head-turn thresholds from the web portal (Attendance.jsx), applied to the same
// landmark-based yaw ratio: dist(noseTip, jaw[2]) / dist(noseTip, jaw[14]).
const double _yawPortalLeftThreshold = 0.65;
const double _yawPortalRightThreshold = 1.50;
const double _yawCenterMin = 0.85;
const double _yawCenterMax = 1.15;
// Only identify from a roughly frontal face.
const double _yawFrontalMin = 0.70;
const double _yawFrontalMax = 1.43;

const int _maxFailedAttempts = 3;
const Duration _faceLostGrace = Duration(milliseconds: 1500);
const Duration _identifyInterval = Duration(milliseconds: 1200);
const Duration _idleFrameInterval = Duration(milliseconds: 350);
const Duration _activeFrameInterval = Duration(milliseconds: 120);

/// Native face attendance terminal - the mobile counterpart of the web portal's
/// Front Desk Attendance page (wp_webapp/src/pages/Attendance.jsx):
///
/// 1. the face inside the guide is described on-device and identified with
///    `/api/attendance/identify-face`,
/// 2. the employee turns their head left and right (liveness), capturing the
///    left and right profile descriptors,
/// 3. attendance is recorded with `/api/attendance/check-in-out-with-face`,
///    where the backend re-verifies the front, left and right descriptors.
///
/// After 3 failed identifications it falls back to email + password (still
/// verified against the live face), like the web portal.
class NativeFaceScannerScreen extends StatefulWidget {
  const NativeFaceScannerScreen({super.key});

  @override
  State<NativeFaceScannerScreen> createState() => _NativeFaceScannerScreenState();
}

class _NativeFaceScannerScreenState extends State<NativeFaceScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  bool _isDisposed = false;

  late final FaceDetector _faceDetector;
  final FaceRecognitionService _engine = FaceRecognitionService.instance;
  bool _modelsReady = false;
  String? _modelError;

  late AnimationController _scanAnimController;
  late Animation<double> _scanAnimation;

  // Frame loop
  bool _processingFrame = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFaceSeenAt = DateTime.fromMillisecondsSinceEpoch(0);
  CameraFaceFrame? _latestFrame;
  FaceRect? _latestBox;
  FaceLandmarks68? _latestLandmarks;

  bool _faceDetected = false;
  String _statusMessage = 'Initializing face scanner...';

  // Identification
  bool _identifying = false;
  DateTime _lastIdentifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _failedAttempts = 0;
  Map<String, String>? _identifiedEmployee; // {email, employeeName}
  Float32List? _frontDescriptor;
  Map<String, dynamic>? _attendanceStatus;
  bool _isLoadingStatus = false;

  // Liveness. Profiles are named like the web portal / backend: the portal's
  // "left" profile (yaw ratio < 0.65) is the employee turning to their own
  // right in the un-mirrored frame, and vice versa.
  bool _lookingCenter = true;
  bool _capturingProfile = false;
  Float32List? _portalLeftDescriptor;
  Float32List? _portalRightDescriptor;
  CameraFaceFrame? _livenessFrame;

  bool get _userTurnedLeft => _portalRightDescriptor != null;
  bool get _userTurnedRight => _portalLeftDescriptor != null;
  bool get _livenessVerified => _portalLeftDescriptor != null && _portalRightDescriptor != null;

  // Password fallback
  bool _passwordMode = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  Timer? _emailDebounce;
  Map<String, dynamic>? _fallbackStatus;
  bool _fallbackStatusLoading = false;

  // Recording
  bool _isRecordingAttendance = false;
  String? _accessDeniedMessage;
  Timer? _accessDeniedTimer;

  final ValueNotifier<int> _resetCountdownNotifier = ValueNotifier<int>(4);
  Timer? _autoResetTimer;

  bool get _isActive => mounted && !_isDisposed;

  bool get _canProcessFrames =>
      _isActive &&
      _modelsReady &&
      !_isRecordingAttendance &&
      !_livenessVerified &&
      _accessDeniedMessage == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.15,
      ),
    );

    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnimController, curve: Curves.easeInOut),
    );

    _loadModels();
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
    _autoResetTimer?.cancel();
    _accessDeniedTimer?.cancel();
    _emailDebounce?.cancel();
    _scanAnimController.dispose();
    _releaseCamera();
    _faceDetector.close();
    _resetCountdownNotifier.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- setup

  Future<void> _loadModels() async {
    try {
      await _engine.load();
      if (!_isActive) return;
      setState(() {
        _modelsReady = true;
        _modelError = null;
        _statusMessage = 'Stand in front of the camera';
      });
    } catch (e) {
      debugPrint('Face recognition models failed to load: $e');
      if (!_isActive) return;
      setState(() {
        _modelError = 'Face recognition models failed to load.';
      });
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!_isActive) return;
    if (status.isGranted) {
      setState(() {
        _isPermissionDenied = false;
      });
      await _setupCameras();
    } else {
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

  // ----------------------------------------------------------- frame loop

  void _onCameraImage(CameraImage image) {
    if (_processingFrame || !_canProcessFrames) return;
    final now = DateTime.now();
    final interval = (_identifiedEmployee != null || _passwordMode) ? _activeFrameInterval : _idleFrameInterval;
    if (now.difference(_lastFrameAt) < interval) return;
    _lastFrameAt = now;
    _processingFrame = true;
    _processFrame(image).whenComplete(() => _processingFrame = false);
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    final controller = _cameraController;
    if (controller == null) return;
    try {
      final frame = CameraFaceFrame.fromCameraImage(
        cameraImage,
        controller.description,
        controller.value.deviceOrientation,
      );
      if (frame == null) return;

      final faces = await _faceDetector.processImage(frame.inputImage);
      if (!_canProcessFrames) return;

      final pick = _pickFace(faces, frame);
      final box = pick.box;
      if (box == null) {
        _onFaceMissing(pick.message);
        return;
      }

      final landmarks = await _engine.detectLandmarks(frame.image, box);
      if (!_canProcessFrames) return;
      if (landmarks == null) {
        _onFaceMissing('Hold still inside the frame');
        return;
      }

      _lastFaceSeenAt = DateTime.now();
      _latestFrame = frame;
      _latestBox = box;
      _latestLandmarks = landmarks;
      if (!_faceDetected) {
        setState(() {
          _faceDetected = true;
        });
      }

      if (_passwordMode || _identifiedEmployee == null) {
        await _identify(frame, box, landmarks);
      } else {
        await _trackHeadTurn(frame, box, landmarks);
      }
    } catch (e) {
      debugPrint('Face frame processing error: $e');
    }
  }

  /// Largest face near the centre of the guide that is big enough, like the web
  /// portal's "inside the circle" and minimum face width checks.
  ({FaceRect? box, String message}) _pickFace(List<Face> faces, CameraFaceFrame frame) {
    if (faces.isEmpty) return (box: null, message: 'Searching...');
    final width = frame.image.width.toDouble();
    final height = frame.image.height.toDouble();
    final boxes = faces.map((f) => frame.uprightBox(f.boundingBox)).toList()
      ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
    final inside = boxes
        .where((b) => (b.centerX - width / 2).abs() <= width * 0.3 && (b.centerY - height * 0.45).abs() <= height * 0.3)
        .toList();
    if (inside.isEmpty) return (box: null, message: 'Move to the center of the frame');
    final largeEnough = inside.where((b) => b.width >= width * 0.22).toList();
    if (largeEnough.isEmpty) return (box: null, message: 'Please move closer to the camera');
    return (box: largeEnough.first, message: 'Face aligned');
  }

  void _onFaceMissing(String message) {
    final lost = DateTime.now().difference(_lastFaceSeenAt) > _faceLostGrace;
    setState(() {
      _faceDetected = false;
      if (_identifiedEmployee == null || lost) {
        _statusMessage = 'Scanning... ($message)';
      }
      if (!lost) return;
      _latestFrame = null;
      _latestLandmarks = null;
      _lookingCenter = true;
      _portalLeftDescriptor = null;
      _portalRightDescriptor = null;
      if (!_passwordMode && _identifiedEmployee != null) {
        _identifiedEmployee = null;
        _frontDescriptor = null;
        _attendanceStatus = null;
        _isLoadingStatus = false;
      }
    });
  }

  Future<void> _identify(CameraFaceFrame frame, FaceRect box, FaceLandmarks68 landmarks) async {
    if (_passwordMode && _emailController.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    if (_identifying || now.difference(_lastIdentifyAt) < _identifyInterval) return;

    final yaw = landmarks.yawRatio;
    if (yaw < _yawFrontalMin || yaw > _yawFrontalMax) {
      if (!_passwordMode) {
        setState(() {
          _statusMessage = 'Look straight at the camera';
        });
      }
      return;
    }

    final attendanceService = context.read<AttendanceService>();
    _identifying = true;
    _lastIdentifyAt = now;
    if (!_passwordMode) {
      setState(() {
        _statusMessage = 'Identifying face...';
      });
    }

    try {
      // Same detector -> landmarks -> descriptor pipeline as the web portal.
      final descriptor = (await _engine.describeFace(frame.image, box))?.descriptor;
      if (descriptor == null || !_canProcessFrames) return;

      final result = await attendanceService.identifyFace(descriptor);
      if (!_canProcessFrames) return;

      if (result['matched'] == true) {
        final email = result['email']?.toString() ?? '';
        final employeeName = result['employeeName']?.toString() ?? email;

        if (_passwordMode) {
          setState(() {
            _emailController.text = email;
            _statusMessage = 'Recognized: $employeeName. Enter password.';
          });
          _lookupFallbackStatus(email);
          return;
        }

        setState(() {
          _identifiedEmployee = {'email': email, 'employeeName': employeeName};
          _frontDescriptor = descriptor;
          _failedAttempts = 0;
          _lookingCenter = true;
          _portalLeftDescriptor = null;
          _portalRightDescriptor = null;
          _attendanceStatus = null;
          _isLoadingStatus = true;
          _statusMessage = 'Recognized: $employeeName. Turn your head left and right.';
        });
        await _fetchTodayAttendanceStatus(email);
      } else if (!_passwordMode) {
        final attempts = _failedAttempts + 1;
        setState(() {
          _failedAttempts = attempts;
          if (attempts >= _maxFailedAttempts) {
            _passwordMode = true;
            _statusMessage = 'Identification failed $attempts times. Please log in manually.';
          } else {
            _statusMessage = 'Face not recognized (Attempt $attempts/$_maxFailedAttempts).';
          }
        });
        if (attempts >= _maxFailedAttempts) {
          _showSnack('Failed to identify after $_maxFailedAttempts retries. Please enter credentials.');
        }
      }
    } catch (e) {
      debugPrint('Face identification error: $e');
      if (_isActive && !_passwordMode) {
        setState(() {
          _statusMessage = 'Could not reach the server. Retrying...';
        });
      }
    } finally {
      _identifying = false;
    }
  }

  Future<void> _trackHeadTurn(CameraFaceFrame frame, FaceRect box, FaceLandmarks68 landmarks) async {
    if (_capturingProfile || _attendanceStatus?['status'] == 'COMPLETED') return;

    final yaw = landmarks.yawRatio;
    if (yaw >= _yawCenterMin && yaw <= _yawCenterMax) {
      _lookingCenter = true;
    }

    final capturePortalLeft = yaw < _yawPortalLeftThreshold && _portalLeftDescriptor == null;
    final capturePortalRight = yaw > _yawPortalRightThreshold && _portalRightDescriptor == null;

    // A turn only counts when it starts from looking straight (web portal rule).
    if ((capturePortalLeft || capturePortalRight) && _lookingCenter) {
      _capturingProfile = true;
      try {
        // Profile descriptors use the web portal's detector pipeline as well.
        final descriptor = (await _engine.describeFace(frame.image, box))?.descriptor;
        if (descriptor == null || !_canProcessFrames || _identifiedEmployee == null) return;
        setState(() {
          _lookingCenter = false;
          if (capturePortalLeft) {
            _portalLeftDescriptor = descriptor;
          } else {
            _portalRightDescriptor = descriptor;
          }
          if (_livenessVerified) {
            _livenessFrame = frame;
            _statusMessage = 'Liveness verified. Tap Confirm to record attendance.';
          } else if (!_userTurnedLeft) {
            _statusMessage = 'Great! Now turn your head left.';
          } else {
            _statusMessage = 'Great! Now turn your head right.';
          }
        });
      } finally {
        _capturingProfile = false;
      }
    }
  }

  Future<void> _fetchTodayAttendanceStatus(String email) async {
    final attendanceService = context.read<AttendanceService>();
    try {
      final status = await attendanceService.getTodayAttendanceStatus(email);
      if (_isActive && _identifiedEmployee?['email'] == email) {
        setState(() {
          _attendanceStatus = status;
          _isLoadingStatus = false;
          if (status['status'] == 'COMPLETED') {
            _statusMessage = '${_identifiedEmployee?['employeeName']} has already completed attendance for today.';
          }
        });
      }
    } catch (_) {
      if (_isActive && _identifiedEmployee?['email'] == email) {
        setState(() {
          _isLoadingStatus = false;
          _attendanceStatus = {'status': 'NOT_CHECKED_IN'};
        });
      }
    }
  }

  // ------------------------------------------------------------ recording

  Future<void> _handleConfirmPressed() async {
    final employee = _identifiedEmployee;
    final frame = _livenessFrame;
    final frontDescriptor = _frontDescriptor;
    if (employee == null || frame == null || frontDescriptor == null || _isRecordingAttendance) return;

    final status = _attendanceStatus?['status']?.toString() ?? 'NOT_CHECKED_IN';
    if (status == 'COMPLETED') return;
    final action = status == 'CHECKED_IN' ? 'CHECK_OUT' : 'CHECK_IN';

    final confirmed = await _showConfirmDialog(
      action: action,
      employeeName: employee['employeeName'] ?? employee['email'] ?? '',
      status: _attendanceStatus,
    );
    if (confirmed != true || !_isActive) return;

    await _recordAttendance(
      email: employee['email'] ?? '',
      employeeName: employee['employeeName'] ?? '',
      action: action,
      faceDescriptor: frontDescriptor,
      faceDescriptorLeft: _portalLeftDescriptor,
      faceDescriptorRight: _portalRightDescriptor,
      frame: frame,
      livenessVerified: true,
      status: _attendanceStatus,
    );
  }

  Future<void> _submitWithPassword() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showSnack('Email and password are required.');
      return;
    }

    final frame = _latestFrame;
    final box = _latestBox;
    if (frame == null ||
        box == null ||
        _latestLandmarks == null ||
        DateTime.now().difference(_lastFaceSeenAt) > _faceLostGrace) {
      _showSnack('Position your face inside the frame.');
      return;
    }

    final status = _fallbackStatus?['status']?.toString();
    if (status == 'COMPLETED') {
      _showSnack('Attendance already completed for today.');
      return;
    }
    final action = status == 'CHECKED_IN' ? 'CHECK_OUT' : 'CHECK_IN';

    setState(() {
      _statusMessage = 'Scanning face. Look directly at the camera...';
    });
    final descriptor = (await _engine.describeFace(frame.image, box))?.descriptor;
    if (!_isActive) return;
    if (descriptor == null) {
      _showSnack('Position your face inside the frame.');
      return;
    }

    await _recordAttendance(
      email: email,
      employeeName: _fallbackStatus?['employeeName']?.toString() ?? email,
      action: action,
      faceDescriptor: descriptor,
      frame: frame,
      password: password,
      status: _fallbackStatus,
    );
  }

  Future<void> _recordAttendance({
    required String email,
    required String employeeName,
    required String action,
    required Float32List faceDescriptor,
    required CameraFaceFrame frame,
    Float32List? faceDescriptorLeft,
    Float32List? faceDescriptorRight,
    bool livenessVerified = false,
    String? password,
    Map<String, dynamic>? status,
  }) async {
    if (_isRecordingAttendance) return;
    final attendanceService = context.read<AttendanceService>();
    final isCheckIn = action == 'CHECK_IN';

    setState(() {
      _isRecordingAttendance = true;
      _statusMessage = 'Logging ${isCheckIn ? 'Check-In' : 'Check-Out'}...';
    });

    String? snapshot;
    try {
      snapshot = await encodeSnapshotDataUrl(frame.image);
    } catch (e) {
      debugPrint('Snapshot encoding failed: $e');
    }
    final position = await _currentPosition();
    final phoneModel = await _phoneModel();

    try {
      final result = await attendanceService.checkInOutWithFace(
        email: email,
        action: action,
        faceDescriptor: faceDescriptor,
        faceDescriptorLeft: faceDescriptorLeft,
        faceDescriptorRight: faceDescriptorRight,
        snapshotImage: snapshot,
        password: password,
        livenessVerified: livenessVerified,
        latitude: position?.latitude,
        longitude: position?.longitude,
        phoneModel: phoneModel,
      );
      if (!_isActive) return;

      final recordedAction = result['type']?.toString() ?? action;
      setState(() {
        _isRecordingAttendance = false;
        _failedAttempts = 0;
        _statusMessage = '${recordedAction == 'CHECK_IN' ? 'Check-In' : 'Check-Out'} logged!';
      });

      await _showCelebrationDialog(
        action: recordedAction,
        employeeName: result['employeeName']?.toString() ?? employeeName,
        timestamp: ISTHelper.formatTime(DateTime.now()),
        duration: recordedAction == 'CHECK_OUT' ? _durationSinceCheckIn(status) : null,
      );

      // Attendance is recorded: go back to the terminal home screen instead of
      // scanning for another face.
      if (mounted && !_isDisposed) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!_isActive) return;
      final message = e is TimeoutException
          ? 'The server took too long to respond. Please try again.'
          : e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _isRecordingAttendance = false;
        _accessDeniedMessage = message;
        _statusMessage = 'Verification failed. Try again.';
      });
      _accessDeniedTimer?.cancel();
      _accessDeniedTimer = Timer(const Duration(seconds: 5), () {
        if (_isActive) _resetScanner();
      });
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

  String? _durationSinceCheckIn(Map<String, dynamic>? status) {
    final raw = status?['checkInRaw']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final checkIn = DateTime.tryParse(raw.contains('T') ? raw : raw.replaceFirst(' ', 'T'));
    if (checkIn == null) return null;
    final diff = DateTime.now().difference(checkIn);
    if (diff.isNegative) return '0h 0m';
    return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }

  void _resetScanner({String message = 'Stand in front of the camera'}) {
    _autoResetTimer?.cancel();
    _accessDeniedTimer?.cancel();
    setState(() {
      _faceDetected = false;
      _identifiedEmployee = null;
      _frontDescriptor = null;
      _attendanceStatus = null;
      _isLoadingStatus = false;
      _lookingCenter = true;
      _portalLeftDescriptor = null;
      _portalRightDescriptor = null;
      _livenessFrame = null;
      _latestFrame = null;
      _latestLandmarks = null;
      _isRecordingAttendance = false;
      _accessDeniedMessage = null;
      _lastIdentifyAt = DateTime.fromMillisecondsSinceEpoch(0);
      _statusMessage = message;
    });
  }

  void _exitPasswordMode() {
    _emailDebounce?.cancel();
    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _passwordMode = false;
      _failedAttempts = 0;
      _fallbackStatus = null;
      _fallbackStatusLoading = false;
    });
    _resetScanner();
  }

  void _onFallbackEmailChanged(String value) {
    _emailDebounce?.cancel();
    _emailDebounce = Timer(const Duration(milliseconds: 600), () => _lookupFallbackStatus(value.trim()));
  }

  Future<void> _lookupFallbackStatus(String email) async {
    if (!_isActive) return;
    if (!email.contains('@')) {
      setState(() {
        _fallbackStatus = null;
        _fallbackStatusLoading = false;
      });
      return;
    }
    final attendanceService = context.read<AttendanceService>();
    setState(() {
      _fallbackStatusLoading = true;
    });
    try {
      final status = await attendanceService.getTodayAttendanceStatus(email);
      if (!_isActive || _emailController.text.trim() != email) return;
      setState(() {
        _fallbackStatus = status;
        _fallbackStatusLoading = false;
      });
    } catch (_) {
      if (!_isActive) return;
      setState(() {
        _fallbackStatus = null;
        _fallbackStatusLoading = false;
      });
    }
  }

  void _showSnack(String message) {
    if (!_isActive) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --------------------------------------------------------------- dialogs

  Future<bool?> _showConfirmDialog({
    required String action,
    required String employeeName,
    Map<String, dynamic>? status,
  }) {
    final isCheckIn = action == 'CHECK_IN';
    final accent = isCheckIn ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final checkInTime = status?['checkInTime']?.toString();

    Widget row(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: valueColor ?? Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return showDialog<bool>(
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
            border: Border.all(color: accent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isCheckIn ? Icons.how_to_reg_rounded : Icons.logout_rounded, color: accent, size: 44),
              const SizedBox(height: 12),
              Text(
                isCheckIn ? 'Confirm Check In' : 'Confirm Check Out',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Please verify the details below before logging.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  children: [
                    row('EMPLOYEE', employeeName),
                    if (isCheckIn)
                      row('CHECK IN TIME', ISTHelper.formatTime(DateTime.now()), valueColor: const Color(0xFF34D399))
                    else ...[
                      row('CHECKED IN AT', checkInTime ?? 'N/A'),
                      row('TOTAL DURATION', _durationSinceCheckIn(status) ?? 'N/A', valueColor: const Color(0xFFFBBF24)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        isCheckIn ? 'Confirm In' : 'Confirm Out',
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
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
                employeeName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isCheckIn ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(height: 14),

              // Timestamp & Details Box
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

              // Auto-close countdown (then the scanner returns to the home screen)
              ValueListenableBuilder<int>(
                valueListenable: _resetCountdownNotifier,
                builder: (context, seconds, _) {
                  return Text(
                    'Returning to home in ${seconds}s...',
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

    _autoResetTimer?.cancel();
  }

  // -------------------------------------------------------------------- UI

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
            else if (_modelError != null)
              _buildModelErrorView()
            else if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized)
              _buildCameraLoadingView()
            else
              _buildCameraPreviewView(),

            // 2. Top Bar (Exit, Live Pill, Flip Camera)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildTopControlBar(),
            ),

            // 3. Central face guide with liveness progress
            if (_isCameraInitialized && !_isPermissionDenied && _modelError == null)
              Center(child: _buildFaceScanningGuide()),

            // 4. Bottom identification / attendance panel
            if (!_isPermissionDenied && _modelError == null)
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
    if (_livenessVerified) {
      pillText = 'LIVENESS VERIFIED';
      pillColor = const Color(0xFF10B981);
    } else if (_identifiedEmployee != null) {
      pillText = 'FACE IDENTIFIED';
      pillColor = const Color(0xFF10B981);
    } else if (!_modelsReady) {
      pillText = 'LOADING';
      pillColor = const Color(0xFF94A3B8);
    } else if (_faceDetected) {
      pillText = 'FACE DETECTED';
      pillColor = const Color(0xFF38BDF8);
    } else {
      pillText = 'STAND IN FRAME';
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

        // Live Biometric Status Pill
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
                size: 20,
              ),
            ),
          )
        else
          const SizedBox(width: 40),
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
              width: _cameraController!.value.previewSize?.height ?? MediaQuery.of(context).size.width,
              height: _cameraController!.value.previewSize?.width ?? MediaQuery.of(context).size.height,
              child: CameraPreview(_cameraController!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaceScanningGuide() {
    final size = MediaQuery.of(context).size;
    final guideWidth = size.width * 0.72;
    final guideHeight = guideWidth * 1.25;

    final Color ringColor = _livenessVerified || _identifiedEmployee != null
        ? const Color(0xFF10B981)
        : _faceDetected
            ? const Color(0xFF38BDF8)
            : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.only(bottom: 140),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Biometric Face Viewfinder Oval
          SizedBox(
            width: guideWidth,
            height: guideHeight,
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(guideWidth / 2),
                    border: Border.all(
                      color: ringColor,
                      width: _livenessVerified ? 4.0 : 3.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ringColor.withValues(alpha: _livenessVerified ? 0.45 : 0.25),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

                // Animated Laser Scanning Beam
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: _scanAnimation.value * (guideHeight - 20),
                      left: 12,
                      right: 12,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              ringColor,
                              Colors.white,
                              ringColor,
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ringColor.withValues(alpha: 0.8),
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
          const SizedBox(height: 14),

          // Progress: Face ID match, then left and right head turns
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLivenessAngleBadge(
                  label: 'Face ID',
                  isDone: _identifiedEmployee != null,
                  icon: Icons.face_rounded,
                ),
                const SizedBox(width: 8),
                _buildLivenessAngleBadge(
                  label: 'Turn Left',
                  isDone: _userTurnedLeft,
                  icon: Icons.arrow_back_rounded,
                ),
                const SizedBox(width: 8),
                _buildLivenessAngleBadge(
                  label: 'Turn Right',
                  isDone: _userTurnedRight,
                  icon: Icons.arrow_forward_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Real-time Guidance Message Tag
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width * 0.9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ringColor.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _livenessVerified
                        ? Icons.verified_user_rounded
                        : _faceDetected
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                    size: 15,
                    color: ringColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _statusMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _livenessVerified ? const Color(0xFF34D399) : Colors.white,
                      ),
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

  Widget _buildLivenessAngleBadge({
    required String label,
    required bool isDone,
    required IconData icon,
  }) {
    final Color color = isDone ? const Color(0xFF10B981) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isDone ? Icons.check_circle_rounded : icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDone ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final Widget content;
    if (_accessDeniedMessage != null) {
      content = _buildAccessDeniedContent();
    } else if (_passwordMode) {
      content = _buildPasswordFallbackContent();
    } else if (_identifiedEmployee != null) {
      content = _buildIdentifiedContent();
    } else {
      content = _buildScanningContent();
    }

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
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
      child: SingleChildScrollView(
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
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildScanningContent() {
    final String message;
    if (!_modelsReady) {
      message = 'Preparing on-device face recognition...';
    } else if (_failedAttempts > 0) {
      message = 'Face not recognized (Attempt $_failedAttempts/$_maxFailedAttempts). Look straight at the camera in good light.';
    } else {
      message = 'Position your face inside the frame. The scanner identifies you automatically.';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Color(0xFF94A3B8),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: const Color(0xFF334155),
              disabledForegroundColor: const Color(0xFF94A3B8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_modelsReady || _identifying)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF94A3B8)),
                  )
                else
                  const Icon(Icons.face_retouching_natural_rounded, size: 22),
                const SizedBox(width: 10),
                Text(
                  _identifying ? 'Identifying...' : 'Waiting for Face',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentifiedContent() {
    final employee = _identifiedEmployee!;
    final status = _attendanceStatus?['status']?.toString() ?? 'NOT_CHECKED_IN';
    final isCheckedIn = status == 'CHECKED_IN';
    final isCompleted = status == 'COMPLETED';
    final employeeName = employee['employeeName'] ?? '';
    final checkInTime = _attendanceStatus?['checkInTime']?.toString();

    return Column(
      children: [
        _buildEmployeeCard(
          name: employeeName,
          subtitle: employee['email'] ?? '',
          status: _isLoadingStatus ? null : status,
        ),
        if (checkInTime != null && checkInTime.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildInfoStrip(Icons.access_time_filled_rounded, 'Check-In Time: $checkInTime'),
        ],
        const SizedBox(height: 14),
        if (isCompleted) ...[
          _buildNoticeCard(
            color: const Color(0xFFF59E0B),
            icon: Icons.info_outline_rounded,
            title: 'Attendance Completed Today',
            body: 'You have already completed both Check-In and Check-Out for today. No further action is required.',
          ),
          const SizedBox(height: 12),
          _buildSecondaryButton('Done / Reset Scanner', Icons.refresh_rounded, _resetScanner),
        ] else if (_livenessVerified) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_isRecordingAttendance || _isLoadingStatus) ? null : _handleConfirmPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: isCheckedIn ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: (isCheckedIn ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                disabledBackgroundColor: const Color(0xFF334155),
              ),
              child: _isRecordingAttendance
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Recording Attendance...',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isCheckedIn ? Icons.logout_rounded : Icons.check_circle_rounded, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          isCheckedIn ? 'Confirm Check-Out' : 'Confirm Check-In',
                          style: const TextStyle(
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
          const SizedBox(height: 8),
          if (!_isRecordingAttendance) _buildSecondaryButton('Not Me? Re-Scan', Icons.refresh_rounded, _resetScanner),
        ] else ...[
          _buildNoticeCard(
            color: const Color(0xFF38BDF8),
            icon: Icons.threed_rotation_rounded,
            title: 'Face Liveness Scan',
            body: 'Turn your head to the left, then to the right, to confirm it is really you.',
          ),
          const SizedBox(height: 8),
          _buildSecondaryButton('Not Me? Re-Scan', Icons.refresh_rounded, _resetScanner),
        ],
      ],
    );
  }

  Widget _buildPasswordFallbackContent() {
    final status = _fallbackStatus?['status']?.toString();
    final isCheckedIn = status == 'CHECKED_IN';
    final isCompleted = status == 'COMPLETED';
    final employeeName = _fallbackStatus?['employeeName']?.toString();

    InputDecoration decoration(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Poppins', color: Color(0xFF64748B), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF38BDF8)),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNoticeCard(
          color: const Color(0xFFF87171),
          icon: Icons.lock_outline_rounded,
          title: 'Manual Verification',
          body: 'Face not recognized after $_maxFailedAttempts attempts. Enter your credentials - your face is still verified.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_isRecordingAttendance,
          onChanged: _onFallbackEmailChanged,
          style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
          decoration: decoration('Enter your email address', Icons.alternate_email_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: true,
          enabled: !_isRecordingAttendance,
          style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
          decoration: decoration('Password', Icons.password_rounded),
        ),
        const SizedBox(height: 8),
        if (_fallbackStatusLoading)
          _buildInfoStrip(Icons.hourglass_top_rounded, 'Checking attendance status...')
        else if (isCheckedIn && employeeName != null)
          _buildInfoStrip(Icons.info_outline_rounded, '$employeeName is currently checked in.')
        else if (isCompleted && employeeName != null)
          _buildInfoStrip(Icons.check_rounded, '$employeeName has completed attendance for today.'),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: (_isRecordingAttendance || isCompleted || _fallbackStatusLoading) ? null : _submitWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: isCheckedIn ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF334155),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isRecordingAttendance
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    isCheckedIn ? 'Check Out' : 'Check In',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (!_isRecordingAttendance)
          _buildSecondaryButton('Try Face Scanner Again', Icons.face_retouching_natural_rounded, _exitPasswordMode),
      ],
    );
  }

  Widget _buildAccessDeniedContent() {
    return Column(
      children: [
        _buildNoticeCard(
          color: const Color(0xFFF87171),
          icon: Icons.gpp_bad_rounded,
          title: 'Access Denied',
          body: _accessDeniedMessage ?? 'Verification failed.',
        ),
        const SizedBox(height: 12),
        _buildSecondaryButton('Retry Verification', Icons.refresh_rounded, _resetScanner),
      ],
    );
  }

  Widget _buildEmployeeCard({required String name, required String subtitle, String? status}) {
    final isCheckedIn = status == 'CHECKED_IN';
    final isCompleted = status == 'COMPLETED';
    final badgeColor = isCompleted
        ? const Color(0xFF64748B)
        : isCheckedIn
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                blurRadius: 10,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : 'U',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 16),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
        if (status == null)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badgeColor),
            ),
            child: Text(
              isCompleted
                  ? 'COMPLETED'
                  : isCheckedIn
                      ? 'CHECKED IN'
                      : 'NOT IN YET',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isCompleted
                    ? const Color(0xFF94A3B8)
                    : isCheckedIn
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF34D399),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoStrip(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard({
    required Color color,
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Color(0xFFCBD5E1), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryButton(String label, IconData icon, VoidCallback onPressed) {
    return Center(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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

  Widget _buildModelErrorView() {
    return Container(
      color: const Color(0xFF0B132B),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFFF87171)),
            const SizedBox(height: 16),
            Text(
              _modelError ?? 'Face recognition is unavailable.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _modelError = null;
                });
                _loadModels();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry', style: TextStyle(fontFamily: 'Poppins')),
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
              'WorkPulse requires camera permission to scan employee faces for attendance.',
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
