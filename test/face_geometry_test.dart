import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attendance_app/utils/face_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expected values in the fixture come from the Python reference pipeline that
/// was verified against @vladmandic/face-api (the library the web portal uses).
void main() {
  final fixture = json.decode(
    File('test/fixtures/face_geometry_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final width = fixture['width'] as int;
  final height = fixture['height'] as int;

  final rgb = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      rgb[i] = (x * 7 + y * 3) % 256;
      rgb[i + 1] = (x * x + y * 5) % 256;
      rgb[i + 2] = (x * y) % 256;
    }
  }
  final image = RgbFaceImage(rgb, width, height);

  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  for (final (index, c) in cases.indexed) {
    group('face-api parity case $index', () {
      final boxJson = c['box'] as Map<String, dynamic>;
      final box = FaceRect(
        (boxJson['x'] as num).toDouble(),
        (boxJson['y'] as num).toDouble(),
        (boxJson['width'] as num).toDouble(),
        (boxJson['height'] as num).toDouble(),
      );
      final crop = detectionCrop(box, width, height);

      test('detection crop', () {
        expect([crop.x, crop.y, crop.width, crop.height], c['crop']);
      });

      test('square network input', () {
        final input = squareInput(image, crop, 112);
        var sum = 0.0;
        for (final v in input) {
          sum += v;
        }
        final expectedSum = (c['input112_sum'] as num).toDouble();
        expect(sum, closeTo(expectedSum, expectedSum.abs() * 1e-6 + 1));
        for (final probe in (c['input112_probes'] as List)) {
          final u = probe[0] as int;
          final v = probe[1] as int;
          final expected = (probe[2] as List).cast<num>();
          for (var ch = 0; ch < 3; ch++) {
            expect(input[(v * 112 + u) * 3 + ch], closeTo(expected[ch].toDouble(), 1e-3), reason: 'pixel ($u, $v) channel $ch');
          }
        }
      });

      final raw = (c['raw'] as List).cast<num>().map((e) => e.toDouble()).toList();
      final landmarks = decodeLandmarks(raw, crop, box);

      test('landmark decoding', () {
        final expected = (c['landmarks'] as List).cast<List>();
        for (var i = 0; i < 68; i++) {
          expect(landmarks.x(i), closeTo((expected[i][0] as num).toDouble(), 1e-6));
          expect(landmarks.y(i), closeTo((expected[i][1] as num).toDouble(), 1e-6));
        }
      });

      test('dlib aligned rect', () {
        final rect = landmarks.alignedFaceRect(width, height);
        expect([rect.x, rect.y, rect.width, rect.height], c['aligned']);
      });

      test('yaw ratio', () {
        expect(landmarks.yawRatio, closeTo((c['yaw'] as num).toDouble(), 1e-9));
      });
    });
  }

  group('camera frame sampling', () {
    // 4x2 sensor frame; luma encodes the sensor index, neutral chroma so RGB == luma.
    Uint8List nv21() {
      final bytes = Uint8List(4 * 2 + 4)..fillRange(8, 12, 128);
      for (var i = 0; i < 8; i++) {
        bytes[i] = 10 * i + 5;
      }
      return bytes;
    }

    double lumaAt(FaceImage img, int x, int y) {
      final out = Float32List(3);
      img.readRgb(x, y, out, 0);
      expect(out[0], out[1]);
      expect(out[1], out[2]);
      return out[0];
    }

    test('NV21 rotated 90 degrees clockwise is upright', () {
      final img = Nv21FaceImage(bytes: nv21(), frameWidth: 4, frameHeight: 2, rotation: 90);
      expect([img.width, img.height], [2, 4]);
      expect(lumaAt(img, 0, 0), 45); // sensor bottom-left -> upright top-left
      expect(lumaAt(img, 1, 0), 5); // sensor top-left -> upright top-right
      expect(lumaAt(img, 0, 3), 75); // sensor bottom-right -> upright bottom-left
    });

    test('NV21 rotated 270 and 180 degrees', () {
      final r270 = Nv21FaceImage(bytes: nv21(), frameWidth: 4, frameHeight: 2, rotation: 270);
      expect([r270.width, r270.height], [2, 4]);
      expect(lumaAt(r270, 0, 0), 35); // sensor top-right -> upright top-left
      expect(lumaAt(r270, 1, 3), 45); // sensor bottom-left -> upright bottom-right
      final r180 = Nv21FaceImage(bytes: nv21(), frameWidth: 4, frameHeight: 2, rotation: 180);
      expect(lumaAt(r180, 0, 0), 75);
    });

    test('NV21 colour conversion (BT.601 full range)', () {
      final bytes = Uint8List(6)
        ..[0] = 100
        ..[1] = 100
        ..[2] = 100
        ..[3] = 100
        ..[4] = 178 // V
        ..[5] = 128; // U
      final img = Nv21FaceImage(bytes: bytes, frameWidth: 2, frameHeight: 2);
      final out = Float32List(3);
      img.readRgb(1, 1, out, 0);
      expect(out[0], closeTo(170.1, 1e-3));
      expect(out[1], closeTo(64.2932, 1e-3));
      expect(out[2], closeTo(100, 1e-3));
    });

    test('BGRA front camera frames are un-mirrored', () {
      const bytesPerRow = 16; // 3 pixels + row padding
      final bytes = Uint8List(bytesPerRow);
      for (var x = 0; x < 3; x++) {
        bytes[x * 4] = x; // B
        bytes[x * 4 + 1] = 10; // G
        bytes[x * 4 + 2] = 200 + x; // R
        bytes[x * 4 + 3] = 255;
      }
      final out = Float32List(3);
      Bgra8888FaceImage(bytes: bytes, width: 3, height: 1, bytesPerRow: bytesPerRow, mirrored: true).readRgb(0, 0, out, 0);
      expect(out, [202, 10, 2]);
      Bgra8888FaceImage(bytes: bytes, width: 3, height: 1, bytesPerRow: bytesPerRow).readRgb(0, 0, out, 0);
      expect(out, [200, 10, 0]);
    });
  });

  test('clipAtImageBorders matches face-api', () {
    final r = clipAtImageBorders(-10.5, 20.2, 50.9, 300.0, 100, 200);
    expect([r.x, r.y, r.width, r.height], [0, 20, 40, 179]);
  });

  test('euclidean distance', () {
    expect(euclideanDistance([0, 3], [4, 0]), 5);
    expect(euclideanDistance([0], [1, 2]), double.infinity);
  });
}
