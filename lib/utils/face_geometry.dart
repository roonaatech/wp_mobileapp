import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart port of the face-api.js (@vladmandic/face-api 1.7.x) steps the web
/// attendance portal runs around its landmark and recognition networks.
///
/// Keeping these steps identical to the browser is what makes descriptors
/// computed on the phone comparable with the Face IDs registered from the web
/// app (the backend matches them with a plain euclidean distance < 0.6).

/// An upright, un-mirrored RGB view over a camera frame, sampled on demand so
/// whole frames never need to be converted.
abstract class FaceImage {
  int get width;
  int get height;

  /// Writes the RGB value (0..255) of pixel ([x], [y]) into [out] at [offset].
  void readRgb(int x, int y, Float32List out, int offset);
}

/// Interleaved 8-bit RGB buffer.
class RgbFaceImage implements FaceImage {
  RgbFaceImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  @override
  final int width;
  @override
  final int height;

  @override
  void readRgb(int x, int y, Float32List out, int offset) {
    final i = (y * width + x) * 3;
    out[offset] = bytes[i].toDouble();
    out[offset + 1] = bytes[i + 1].toDouble();
    out[offset + 2] = bytes[i + 2].toDouble();
  }
}

/// Android camera frame in NV21. [rotation] is the clockwise rotation (0, 90,
/// 180, 270) that makes the frame upright - the same value handed to ML Kit,
/// whose face boxes are reported in that upright space.
class Nv21FaceImage implements FaceImage {
  Nv21FaceImage({
    required this.bytes,
    required this.frameWidth,
    required this.frameHeight,
    this.rotation = 0,
  }) : _uvRowStride = ((frameWidth + 1) >> 1) * 2;

  final Uint8List bytes;
  final int frameWidth;
  final int frameHeight;
  final int rotation;
  final int _uvRowStride;

  bool get _swapsAxes => rotation == 90 || rotation == 270;

  @override
  int get width => _swapsAxes ? frameHeight : frameWidth;

  @override
  int get height => _swapsAxes ? frameWidth : frameHeight;

  @override
  void readRgb(int x, int y, Float32List out, int offset) {
    final int sx;
    final int sy;
    switch (rotation) {
      case 90:
        sx = y;
        sy = frameHeight - 1 - x;
      case 180:
        sx = frameWidth - 1 - x;
        sy = frameHeight - 1 - y;
      case 270:
        sx = frameWidth - 1 - y;
        sy = x;
      default:
        sx = x;
        sy = y;
    }
    final luma = bytes[sy * frameWidth + sx].toDouble();
    final uv = frameWidth * frameHeight + (sy >> 1) * _uvRowStride + (sx >> 1) * 2;
    final v = bytes[uv] - 128.0;
    final u = bytes[uv + 1] - 128.0;
    out[offset] = _clampByte(luma + 1.402 * v);
    out[offset + 1] = _clampByte(luma - 0.344136 * u - 0.714136 * v);
    out[offset + 2] = _clampByte(luma + 1.772 * u);
  }
}

/// iOS camera frame in BGRA8888. camera_avfoundation already delivers frames
/// upright, but mirrors the front camera; [mirrored] undoes that so faces look
/// like the (un-mirrored) webcam frames the web portal registers.
class Bgra8888FaceImage implements FaceImage {
  Bgra8888FaceImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    this.mirrored = false,
  });

  final Uint8List bytes;
  @override
  final int width;
  @override
  final int height;
  final int bytesPerRow;
  final bool mirrored;

  @override
  void readRgb(int x, int y, Float32List out, int offset) {
    final bx = mirrored ? width - 1 - x : x;
    final i = y * bytesPerRow + bx * 4;
    out[offset] = bytes[i + 2].toDouble();
    out[offset + 1] = bytes[i + 1].toDouble();
    out[offset + 2] = bytes[i].toDouble();
  }
}

double _clampByte(double v) => v < 0 ? 0 : (v > 255 ? 255 : v);

class FaceRect {
  const FaceRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  /// The same rectangle in a horizontally mirrored image of [imageWidth].
  FaceRect mirrored(int imageWidth) => FaceRect(imageWidth - right, y, width, height);

  @override
  String toString() => 'FaceRect(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)})';
}

class PixelRect {
  const PixelRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  bool get isEmpty => width <= 0 || height <= 0;
}

/// face-api `Box.clipAtImageBorders` (including its trailing `floor()`).
PixelRect clipAtImageBorders(
  double x,
  double y,
  double width,
  double height,
  int imageWidth,
  int imageHeight,
) {
  final clippedX = math.max(x, 0.0);
  final clippedY = math.max(y, 0.0);
  final clippedWidth = math.min(x + width - clippedX, imageWidth - clippedX);
  final clippedHeight = math.min(y + height - clippedY, imageHeight - clippedY);
  return PixelRect(clippedX.floor(), clippedY.floor(), clippedWidth.floor(), clippedHeight.floor());
}

/// face-api `extractFaces` for a detection: `box.floor().clipAtImageBorders()`.
PixelRect detectionCrop(FaceRect box, int imageWidth, int imageHeight) => clipAtImageBorders(
      box.x.floorToDouble(),
      box.y.floorToDouble(),
      box.width.floorToDouble(),
      box.height.floorToDouble(),
      imageWidth,
      imageHeight,
    );

/// face-api `imageToSquare(crop, size, centerImage: true)` + `fromPixels`: the
/// longer side is scaled to [size], centred on a black square and bilinearly
/// sampled like a 2D canvas draw. Returns `size * size * 3` RGB values.
Float32List squareInput(FaceImage image, PixelRect crop, int size) {
  final out = Float32List(size * size * 3);
  if (crop.isEmpty) return out;

  final w = crop.width;
  final h = crop.height;
  final scale = size / math.max(w, h);
  final drawnW = w * scale;
  final drawnH = h * scale;
  final offset = (drawnW - drawnH).abs() / 2;
  final dx = drawnW < drawnH ? offset : 0.0;
  final dy = drawnH < drawnW ? offset : 0.0;

  final xs = _SampleAxis(size, dx, drawnW, scale, w);
  final ys = _SampleAxis(size, dy, drawnH, scale, h);

  final p00 = Float32List(3);
  final p10 = Float32List(3);
  final p01 = Float32List(3);
  final p11 = Float32List(3);
  for (var v = 0; v < size; v++) {
    if (!ys.valid[v]) continue;
    final y0 = crop.y + ys.lo[v];
    final y1 = crop.y + ys.hi[v];
    final fy = ys.frac[v];
    for (var u = 0; u < size; u++) {
      if (!xs.valid[u]) continue;
      final x0 = crop.x + xs.lo[u];
      final x1 = crop.x + xs.hi[u];
      final fx = xs.frac[u];
      image.readRgb(x0, y0, p00, 0);
      image.readRgb(x1, y0, p10, 0);
      image.readRgb(x0, y1, p01, 0);
      image.readRgb(x1, y1, p11, 0);
      final o = (v * size + u) * 3;
      for (var c = 0; c < 3; c++) {
        final top = p00[c] + (p10[c] - p00[c]) * fx;
        final bottom = p01[c] + (p11[c] - p01[c]) * fx;
        out[o + c] = top + (bottom - top) * fy;
      }
    }
  }
  return out;
}

class _SampleAxis {
  _SampleAxis(int size, double start, double drawn, double scale, int sourceLength)
      : valid = List<bool>.filled(size, false),
        lo = Int32List(size),
        hi = Int32List(size),
        frac = Float64List(size) {
    final maxIndex = (sourceLength - 1).toDouble();
    for (var i = 0; i < size; i++) {
      final center = i + 0.5;
      valid[i] = center >= start && center < start + drawn;
      final s = math.min(math.max((center - start) / scale - 0.5, 0.0), maxIndex);
      final f = s.floor();
      lo[i] = f;
      hi[i] = math.min(f + 1, sourceLength - 1);
      frac[i] = s - f;
    }
  }

  final List<bool> valid;
  final Int32List lo;
  final Int32List hi;
  final Float64List frac;
}

/// 68-point landmarks in absolute image coordinates.
class FaceLandmarks68 {
  FaceLandmarks68(this.points, this.cropWidth, this.cropHeight);

  /// Interleaved x0, y0, x1, y1, ...
  final Float64List points;

  /// Size of the detection crop the landmarks were predicted from.
  final int cropWidth;
  final int cropHeight;

  double x(int i) => points[2 * i];
  double y(int i) => points[2 * i + 1];

  /// Web portal head-turn metric (Attendance.jsx `calculateYawRatio`):
  /// dist(noseTip, jaw[2]) / dist(noseTip, jaw[14]). < 0.65 is the portal's
  /// "left" turn, > 1.50 its "right" turn, 0.85..1.15 looking straight.
  double get yawRatio {
    final nx = x(30);
    final ny = y(30);
    final left = _hypot(nx - x(2), ny - y(2));
    final right = _hypot(nx - x(14), ny - y(14));
    if (right == 0) return 1.0;
    return left / right;
  }

  /// face-api `FaceLandmarks.alignDlib` followed by `clipAtImageBorders`: the
  /// region that is fed to the recognition net.
  PixelRect alignedFaceRect(int imageWidth, int imageHeight) {
    final leftEye = _center(36, 42);
    final rightEye = _center(42, 48);
    final mouth = _center(48, 68);
    final eyeToMouth = (_hypot(mouth.$1 - leftEye.$1, mouth.$2 - leftEye.$2) +
            _hypot(mouth.$1 - rightEye.$1, mouth.$2 - rightEye.$2)) /
        2;
    final size = (eyeToMouth / 0.45).floor();
    final refX = (leftEye.$1 + rightEye.$1 + mouth.$1) / 3;
    final refY = (leftEye.$2 + rightEye.$2 + mouth.$2) / 3;
    final rx = math.max(0.0, refX - 0.5 * size).floor();
    final ry = math.max(0.0, refY - 0.43 * size).floor();
    final rw = math.min(size, cropWidth + rx);
    final rh = math.min(size, cropHeight + ry);
    return clipAtImageBorders(
      rx.toDouble(),
      ry.toDouble(),
      rw.toDouble(),
      rh.toDouble(),
      imageWidth,
      imageHeight,
    );
  }

  (double, double) _center(int from, int to) {
    var sx = 0.0;
    var sy = 0.0;
    for (var i = from; i < to; i++) {
      sx += x(i);
      sy += y(i);
    }
    return (sx / (to - from), sy / (to - from));
  }
}

/// `FaceLandmark68Net.postProcess` + landmark shift: converts the raw 136 net
/// outputs (relative to the padded [inputSize] square of [crop]) to absolute
/// image coordinates. face-api shifts by the un-floored detection origin.
FaceLandmarks68 decodeLandmarks(
  List<double> raw,
  PixelRect crop,
  FaceRect detection, {
  int inputSize = 112,
}) {
  final w = crop.width.toDouble();
  final h = crop.height.toDouble();
  final scale = inputSize / math.max(w, h);
  final scaledW = w * scale;
  final scaledH = h * scale;
  final padX = scaledW < scaledH ? (scaledW - scaledH).abs() / 2 : 0.0;
  final padY = scaledH < scaledW ? (scaledW - scaledH).abs() / 2 : 0.0;
  final points = Float64List(136);
  for (var i = 0; i < 68; i++) {
    points[2 * i] = (raw[2 * i] * inputSize - padX) / scaledW * w + detection.x;
    points[2 * i + 1] = (raw[2 * i + 1] * inputSize - padY) / scaledH * h + detection.y;
  }
  return FaceLandmarks68(points, crop.width, crop.height);
}

double euclideanDistance(List<double> a, List<double> b) {
  if (a.length != b.length) return double.infinity;
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    sum += d * d;
  }
  return math.sqrt(sum);
}

double _hypot(double a, double b) => math.sqrt(a * a + b * b);
