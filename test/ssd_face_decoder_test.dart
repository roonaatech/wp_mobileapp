import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attendance_app/utils/face_geometry.dart';
import 'package:attendance_app/utils/ssd_face_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expected values come from the Python port of face-api's SsdMobilenetv1,
/// which reproduces face-api.js detections (box error < 0.01 px).
void main() {
  final fixture = json.decode(
    File('test/fixtures/ssd_fixture.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('decodes SSD output like face-api locateFaces', () {
    final output = Float32List(5118 * 5);
    for (final row in (fixture['rows'] as List)) {
      final i = row[0] as int;
      for (var k = 0; k < 5; k++) {
        output[i * 5 + k] = (row[k + 1] as num).toDouble();
      }
    }

    final faces = decodeSsdDetections(
      output,
      imageWidth: fixture['width'] as int,
      imageHeight: fixture['height'] as int,
    );

    final expected = (fixture['detections'] as List).cast<Map<String, dynamic>>();
    expect(faces.length, expected.length);
    for (var i = 0; i < faces.length; i++) {
      expect(faces[i].box.x, closeTo((expected[i]['x'] as num).toDouble(), 1e-3));
      expect(faces[i].box.y, closeTo((expected[i]['y'] as num).toDouble(), 1e-3));
      expect(faces[i].box.width, closeTo((expected[i]['width'] as num).toDouble(), 1e-3));
      expect(faces[i].box.height, closeTo((expected[i]['height'] as num).toDouble(), 1e-3));
      expect(faces[i].score, closeTo((expected[i]['score'] as num).toDouble(), 1e-6));
    }
  });

  test('overlapping detections are suppressed and low scores dropped', () {
    final output = Float32List(5118 * 5);
    void put(int i, List<double> row) {
      for (var k = 0; k < 5; k++) {
        output[i * 5 + k] = row[k];
      }
    }

    put(10, [0.10, 0.10, 0.50, 0.50, 0.90]);
    put(11, [0.12, 0.11, 0.51, 0.52, 0.80]); // same face, lower score -> suppressed
    put(12, [0.60, 0.60, 0.90, 0.90, 0.70]); // separate face
    put(13, [0.60, 0.10, 0.90, 0.40, 0.40]); // below minConfidence

    final faces = decodeSsdDetections(output, imageWidth: 512, imageHeight: 512);
    expect(faces.map((f) => f.score).toList(), [closeTo(0.9, 1e-6), closeTo(0.7, 1e-6)]);
    expect(faces.first.box.x, closeTo(51.2, 1e-3));
    expect(faces.first.box.width, closeTo(204.8, 1e-3));
  });

  test('top-left square input matches face-api imageToSquare(centerImage: false)', () {
    const width = 320;
    const height = 240;
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        rgb[i] = (x * 7 + y * 3) % 256;
        rgb[i + 1] = (x * x + y * 5) % 256;
        rgb[i + 2] = (x * y) % 256;
      }
    }

    final input = squareInput(
      RgbFaceImage(rgb, width, height),
      const PixelRect(0, 0, width, height),
      64,
      center: false,
    );

    final expected = fixture['topleft64'] as Map<String, dynamic>;
    var sum = 0.0;
    for (final v in input) {
      sum += v;
    }
    final expectedSum = (expected['sum'] as num).toDouble();
    expect(sum, closeTo(expectedSum, expectedSum.abs() * 1e-6 + 1));
    for (final probe in (expected['probes'] as List)) {
      final u = probe[0] as int;
      final v = probe[1] as int;
      final values = (probe[2] as List).cast<num>();
      for (var c = 0; c < 3; c++) {
        expect(input[(v * 64 + u) * 3 + c], closeTo(values[c].toDouble(), 1e-3), reason: 'pixel ($u, $v) channel $c');
      }
    }
  });
}
