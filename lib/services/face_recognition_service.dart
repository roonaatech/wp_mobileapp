import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/face_geometry.dart';

/// On-device port of the face recognition pipeline used by the web attendance
/// portal (face-api.js): FaceLandmark68Net -> dlib alignment ->
/// FaceRecognitionNet.
///
/// The bundled TFLite models were converted from the exact weights the web app
/// loads, so the 128-d descriptors produced here are matched by the backend
/// against Face IDs registered from the browser.
class FaceRecognitionService {
  FaceRecognitionService({this.assetPrefix = ''});

  /// Shared instance - loading the models takes a moment, so keep them warm.
  static final FaceRecognitionService instance = FaceRecognitionService();

  static const String landmarkModelAsset = 'assets/models/face_landmark_68.tflite';
  static const String recognitionModelAsset = 'assets/models/face_recognition.tflite';
  static const int landmarkInputSize = 112;
  static const int recognitionInputSize = 150;
  static const int descriptorLength = 128;

  /// Prefix for the asset keys, e.g. `packages/attendance_app/` when the models
  /// are loaded from another package.
  final String assetPrefix;

  IsolateInterpreter? _landmarkRunner;
  IsolateInterpreter? _recognitionRunner;
  Future<void>? _loading;
  Future<void> _queue = Future<void>.value();

  bool get isLoaded => _landmarkRunner != null && _recognitionRunner != null;

  Future<void> load() {
    return _loading ??= _load().catchError((Object error, StackTrace stackTrace) {
      _loading = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _load() async {
    final landmark = await _createInterpreter(landmarkModelAsset, threads: 2);
    final recognition = await _createInterpreter(recognitionModelAsset, threads: 4);
    _landmarkRunner = await IsolateInterpreter.create(address: landmark.address, debugName: 'FaceLandmarks');
    _recognitionRunner = await IsolateInterpreter.create(address: recognition.address, debugName: 'FaceRecognition');
  }

  Future<Interpreter> _createInterpreter(String asset, {required int threads}) async {
    final data = await rootBundle.load('$assetPrefix$asset');
    final interpreter = Interpreter.fromBuffer(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      options: InterpreterOptions()..threads = threads,
    );
    interpreter.allocateTensors();
    return interpreter;
  }

  /// 68 face landmarks for a face that ML Kit found at [detectorBox] in [image].
  /// Returns null when the face is too small or cut off.
  ///
  /// The web portal crops with SSD-MobileNet boxes; ML Kit boxes are used as-is
  /// because re-framing them to the SSD shape did not bring descriptors any
  /// closer to face-api.js on the reference images.
  Future<FaceLandmarks68?> detectLandmarks(FaceImage image, FaceRect detectorBox) {
    return _serial(() async {
      final crop = detectionCrop(detectorBox, image.width, image.height);
      if (crop.width < 32 || crop.height < 32) return null;
      final input = squareInput(image, crop, landmarkInputSize);
      final raw = await _run(_landmarkRunner, input, 136);
      return decodeLandmarks(raw, crop, detectorBox, inputSize: landmarkInputSize);
    });
  }

  /// The 128-d face descriptor (face-api `computeFaceDescriptor`) of the face
  /// described by [landmarks].
  Future<Float32List?> computeDescriptor(FaceImage image, FaceLandmarks68 landmarks) {
    return _serial(() async {
      final rect = landmarks.alignedFaceRect(image.width, image.height);
      if (rect.width < 32 || rect.height < 32) return null;
      final input = squareInput(image, rect, recognitionInputSize);
      return _run(_recognitionRunner, input, descriptorLength);
    });
  }

  Future<Float32List> _run(IsolateInterpreter? runner, Float32List input, int outputLength) async {
    if (runner == null) {
      throw StateError('FaceRecognitionService.load() must complete before inference');
    }
    final output = Float32List(outputLength);
    // A ByteBuffer output is filled in place by tflite_flutter.
    await runner.run(input.buffer.asUint8List(), output.buffer);
    return output;
  }

  /// IsolateInterpreter silently skips a run while another is in flight, so
  /// all inference goes through one queue.
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
