import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'face_geometry.dart';

/// Small JPEG data URL of the upright, un-mirrored frame for the attendance
/// audit trail (the web portal uploads its webcam frame the same way). Kept
/// small because the backend's JSON body limit is 100 KB.
Future<String> encodeSnapshotDataUrl(
  FaceImage image, {
  int maxSide = 320,
  int quality = 70,
}) async {
  final scale = math.min(1.0, maxSide / math.max(image.width, image.height));
  final width = math.max(1, (image.width * scale).round());
  final height = math.max(1, (image.height * scale).round());
  final rgb = Uint8List(width * height * 3);
  final pixel = Float32List(3);
  for (var y = 0; y < height; y++) {
    final sy = math.min(image.height - 1, ((y + 0.5) / scale).floor());
    for (var x = 0; x < width; x++) {
      final sx = math.min(image.width - 1, ((x + 0.5) / scale).floor());
      image.readRgb(sx, sy, pixel, 0);
      final o = (y * width + x) * 3;
      rgb[o] = pixel[0].round();
      rgb[o + 1] = pixel[1].round();
      rgb[o + 2] = pixel[2].round();
    }
  }
  final jpeg = await compute(_encodeJpeg, _JpegJob(rgb, width, height, quality));
  return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}

class _JpegJob {
  const _JpegJob(this.rgb, this.width, this.height, this.quality);

  final Uint8List rgb;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpeg(_JpegJob job) {
  final picture = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgb.buffer,
    numChannels: 3,
  );
  return img.encodeJpg(picture, quality: job.quality);
}
