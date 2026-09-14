import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_geometry.dart';

/// One camera frame prepared for ML Kit (face detection) and for the face-api
/// port (landmarks + descriptor), with both agreeing on upright, un-mirrored
/// image coordinates.
///
/// * Android (CameraX, NV21): frames are un-mirrored sensor images; ML Kit gets
///   the clockwise rotation and reports boxes in the rotated (upright) space.
/// * iOS (AVFoundation, BGRA): frames are already upright, but the front camera
///   is mirrored and ML Kit ignores rotation metadata, so boxes are flipped back.
class CameraFaceFrame {
  CameraFaceFrame._(this.inputImage, this.image, this._detectorMirrored);

  final InputImage inputImage;
  final FaceImage image;
  final bool _detectorMirrored;

  /// Converts an ML Kit bounding box into [image] coordinates.
  FaceRect uprightBox(Rect detectorBox) {
    final box = FaceRect(detectorBox.left, detectorBox.top, detectorBox.width, detectorBox.height);
    return _detectorMirrored ? box.mirrored(image.width) : box;
  }

  static const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Returns null for formats this pipeline does not handle.
  static CameraFaceFrame? fromCameraImage(
    CameraImage frame,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (frame.planes.isEmpty) return null;
    final plane = frame.planes.first;
    final size = Size(frame.width.toDouble(), frame.height.toDouble());

    if (Platform.isAndroid) {
      if (frame.format.group != ImageFormatGroup.nv21) return null;
      final deviceDegrees = _deviceOrientationDegrees[deviceOrientation] ?? 0;
      final rotation = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + deviceDegrees) % 360
          : (camera.sensorOrientation - deviceDegrees + 360) % 360;
      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: InputImageRotationValue.fromRawValue(rotation) ?? InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final image = Nv21FaceImage(
        bytes: plane.bytes,
        frameWidth: frame.width,
        frameHeight: frame.height,
        rotation: rotation,
      );
      return CameraFaceFrame._(inputImage, image, false);
    }

    if (Platform.isIOS) {
      if (frame.format.group != ImageFormatGroup.bgra8888) return null;
      final mirrored = camera.lensDirection == CameraLensDirection.front;
      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: size,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final image = Bgra8888FaceImage(
        bytes: plane.bytes,
        width: frame.width,
        height: frame.height,
        bytesPerRow: plane.bytesPerRow,
        mirrored: mirrored,
      );
      return CameraFaceFrame._(inputImage, image, mirrored);
    }

    return null;
  }
}
