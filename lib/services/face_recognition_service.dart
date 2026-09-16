import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/face_geometry.dart';
import '../utils/ssd_face_decoder.dart';

/// On-device port of the face pipeline used by the web attendance portal
/// (face-api.js): SSD MobileNet v1 face detector -> FaceLandmark68Net -> dlib
/// alignment -> FaceRecognitionNet.
///
/// The bundled TFLite models were converted from the exact weights the web app
/// loads, so the 128-d descriptors produced here are matched by the backend
/// against Face IDs registered from the browser.
class FaceRecognitionService {
  FaceRecognitionService({this.assetPrefix = ''});

  /// Shared instance - loading the models takes a moment, so keep them warm.
  static final FaceRecognitionService instance = FaceRecognitionService();

  static const String detectorModelAsset = 'assets/models/ssd_mobilenetv1.tflite';
  static const String landmarkModelAsset = 'assets/models/face_landmark_68.tflite';
  static const String recognitionModelAsset = 'assets/models/face_recognition.tflite';
  static const int landmarkInputSize = 112;
  static const int recognitionInputSize = 150;
  static const int descriptorLength = 128;
  static const int _detectorOutputLength = 5118 * 5;

  /// Prefix for the asset keys, e.g. `packages/attendance_app/` when the models
  /// are loaded from another package.
  final String assetPrefix;

  IsolateInterpreter? _detectorRunner;
  IsolateInterpreter? _landmarkRunner;
  IsolateInterpreter? _recognitionRunner;
  Future<void>? _loading;
  Future<void> _queue = Future<void>.value();

  bool get isLoaded => _detectorRunner != null && _landmarkRunner != null && _recognitionRunner != null;

  Future<void> load() {
    return _loading ??= _load().catchError((Object error, StackTrace stackTrace) {
      _loading = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _load() async {
    final detector = await _createInterpreter(detectorModelAsset, threads: 4);
    final landmark = await _createInterpreter(landmarkModelAsset, threads: 2);
    final recognition = await _createInterpreter(recognitionModelAsset, threads: 4);
    _detectorRunner = await IsolateInterpreter.create(address: detector.address, debugName: 'FaceDetector');
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

  /// Faces found by face-api's SSD MobileNet v1, the web portal's face detector.
  Future<List<DetectedFace>> detectFaces(FaceImage image) {
    return _serial(() async {
      final input = squareInput(
        image,
        PixelRect(0, 0, image.width, image.height),
        ssdInputSize,
        center: false,
      );
      final raw = await _run(_detectorRunner, input, _detectorOutputLength);
      return decodeSsdDetections(raw, imageWidth: image.width, imageHeight: image.height);
    });
  }

  /// Describes the face that ML Kit is tracking at [trackedBox] exactly like
  /// the web portal: SSD detection -> landmarks -> 128-d descriptor. Returns
  /// null when the SSD detector does not find that face, or it is cut off.
  Future<FaceDescription?> describeFace(FaceImage image, FaceRect trackedBox) async {
    final faces = await detectFaces(image);
    DetectedFace? match;
    var bestOverlap = 0.25;
    for (final face in faces) {
      final overlap = _overlap(face.box, trackedBox);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        match = face;
      }
    }

    final effectiveBox = match?.box ?? trackedBox;
    final landmarks = await detectLandmarks(image, effectiveBox);
    if (landmarks == null) return null;
    final descriptor = await computeDescriptor(image, landmarks);
    if (descriptor == null) return null;
    return FaceDescription(effectiveBox, landmarks, descriptor);
  }

  /// 68 face landmarks for the face at [faceBox] in [image]: an SSD box when
  /// describing a face, or the cheaper ML Kit box for live head-turn tracking.
  /// Returns null when the face is too small or cut off.
  Future<FaceLandmarks68?> detectLandmarks(FaceImage image, FaceRect faceBox) {
    return _serial(() async {
      final crop = detectionCrop(faceBox, image.width, image.height);
      if (crop.width < 32 || crop.height < 32) return null;
      final input = squareInput(image, crop, landmarkInputSize);
      final raw = await _run(_landmarkRunner, input, 136);
      return decodeLandmarks(raw, crop, faceBox, inputSize: landmarkInputSize);
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

  static double _overlap(FaceRect a, FaceRect b) {
    final w = math.max(0.0, math.min(a.right, b.right) - math.max(a.x, b.x));
    final h = math.max(0.0, math.min(a.bottom, b.bottom) - math.max(a.y, b.y));
    final intersection = w * h;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0.0 : intersection / union;
  }
}

/// A face described with the web portal's pipeline.
class FaceDescription {
  const FaceDescription(this.box, this.landmarks, this.descriptor);

  /// SSD detection box in image pixels.
  final FaceRect box;
  final FaceLandmarks68 landmarks;
  final Float32List descriptor;
}
