import 'dart:math' as math;
import 'dart:typed_data';

import 'face_geometry.dart';

/// Size of the square input of face-api's SSD MobileNet v1 face detector.
const int ssdInputSize = 512;

class DetectedFace {
  const DetectedFace(this.box, this.score);

  /// Face box in image pixels.
  final FaceRect box;
  final double score;
}

/// face-api `SsdMobilenetv1.locateFaces` post-processing - the web portal's
/// face detector - applied to the bundled TFLite model output.
///
/// [output] holds one row per anchor: (ymin, xmin, ymax, xmax, score), with box
/// coordinates relative to the [ssdInputSize] square the image was drawn into
/// (top-left aligned, like face-api's `toBatchTensor(512, false)`).
List<DetectedFace> decodeSsdDetections(
  Float32List output, {
  required int imageWidth,
  required int imageHeight,
  double minConfidence = 0.5,
  double iouThreshold = 0.5,
  int maxResults = 100,
}) {
  final count = output.length ~/ 5;
  double score(int i) => output[i * 5 + 4];

  final candidates = <int>[
    for (var i = 0; i < count; i++)
      if (score(i) > minConfidence) i,
  ]..sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      return byScore != 0 ? byScore : a.compareTo(b);
    });

  // face-api nonMaxSuppression
  final outputSize = math.min(maxResults, count);
  final selected = <int>[];
  for (final candidate in candidates) {
    if (selected.length >= outputSize) break;
    final originalScore = score(candidate);
    var candidateScore = originalScore;
    for (var j = selected.length - 1; j >= 0; j--) {
      final overlap = _iou(output, candidate, selected[j]);
      if (overlap == 0.0) continue;
      candidateScore *= overlap <= iouThreshold ? 1 : 0;
      if (candidateScore <= minConfidence) break;
    }
    if (originalScore == candidateScore) selected.add(candidate);
  }

  // Undo the bottom/right padding of the input square, then scale to pixels.
  final scale = ssdInputSize / math.max(imageWidth, imageHeight);
  final padX = ssdInputSize / (imageWidth * scale).round();
  final padY = ssdInputSize / (imageHeight * scale).round();
  return [
    for (final i in selected)
      () {
        final o = i * 5;
        final top = math.max(0.0, output[o]) * padY;
        final bottom = math.min(1.0, output[o + 2]) * padY;
        final left = math.max(0.0, output[o + 1]) * padX;
        final right = math.min(1.0, output[o + 3]) * padX;
        return DetectedFace(
          FaceRect(left * imageWidth, top * imageHeight, (right - left) * imageWidth, (bottom - top) * imageHeight),
          output[o + 4],
        );
      }(),
  ];
}

double _iou(Float32List b, int i, int j) {
  final oi = i * 5;
  final oj = j * 5;
  final yminI = math.min(b[oi], b[oi + 2]);
  final xminI = math.min(b[oi + 1], b[oi + 3]);
  final ymaxI = math.max(b[oi], b[oi + 2]);
  final xmaxI = math.max(b[oi + 1], b[oi + 3]);
  final yminJ = math.min(b[oj], b[oj + 2]);
  final xminJ = math.min(b[oj + 1], b[oj + 3]);
  final ymaxJ = math.max(b[oj], b[oj + 2]);
  final xmaxJ = math.max(b[oj + 1], b[oj + 3]);
  final areaI = (ymaxI - yminI) * (xmaxI - xminI);
  final areaJ = (ymaxJ - yminJ) * (xmaxJ - xminJ);
  if (areaI <= 0 || areaJ <= 0) return 0.0;
  final intersection = math.max(math.min(ymaxI, ymaxJ) - math.max(yminI, yminJ), 0.0) *
      math.max(math.min(xmaxI, xmaxJ) - math.max(xminI, xminJ), 0.0);
  return intersection / (areaI + areaJ - intersection);
}
