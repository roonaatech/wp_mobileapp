import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandLogoPainter(size),
        size: Size(size, size),
      ),
    );
  }
}

class _BrandLogoPainter extends CustomPainter {
  final double logoSize;
  _BrandLogoPainter(this.logoSize);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Gradient definition
    final brandGradient = const LinearGradient(
      colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
    
    final calGradient = const LinearGradient(
      colors: [Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // 1. Outer Circle (SVG: cx=50, cy=50, r=46, strokeWidth=6)
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..shader = brandGradient.createShader(
        Rect.fromCircle(center: center, radius: w * 0.46),
      )
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, w * 0.46, outerPaint);

    // Scale factor for inner group (0.75)
    final scale = 0.75;
    final innerW = w * scale;
    final innerH = h * scale;
    final innerOffset = Offset(w / 2 - innerW / 2, h / 2 - innerH / 2);

    // 2. Calendar Body (SVG: rect x=22, y=25, width=56, height=50)
    final calendarLeft = innerOffset.dx + innerW * (22 / 100);
    final calendarTop = innerOffset.dy + innerH * (25 / 100);
    final calendarWidth = innerW * (56 / 100);
    final calendarHeight = innerH * (50 / 100);

    final calendarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(calendarLeft, calendarTop, calendarWidth, calendarHeight),
      Radius.circular(w * 0.03),
    );

    final calendarPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = calGradient.createShader(
        Rect.fromLTWH(calendarLeft, calendarTop, calendarWidth, calendarHeight),
      );

    canvas.drawRRect(calendarRect, calendarPaint);

    // Calendar border
    final calBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..color = const Color(0xFF9CA3AF);

    canvas.drawRRect(calendarRect, calBorderPaint);

    // 3. Calendar Rings (SVG: paths for rings at top)
    final ringPaint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..strokeWidth = w * 0.04
      ..strokeCap = StrokeCap.round;

    // Left ring
    final ring1X = innerOffset.dx + innerW * (35 / 100);
    final ring1Y1 = innerOffset.dy + innerH * (20 / 100);
    final ring1Y2 = ring1Y1 + innerH * 0.1;
    canvas.drawLine(Offset(ring1X, ring1Y1), Offset(ring1X, ring1Y2), ringPaint);

    // Right ring
    final ring2X = innerOffset.dx + innerW * (65 / 100);
    canvas.drawLine(Offset(ring2X, ring1Y1), Offset(ring2X, ring1Y2), ringPaint);

    // 4. Calendar Grid (8 boxes in 2 rows of 4)
    final gridStartY = calendarTop + innerH * 0.15;
    final gridStartX = calendarLeft + innerW * 0.06;
    final boxSize = innerW * 0.08;
    final boxSpacing = innerW * 0.12;

    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 4; col++) {
        final x = gridStartX + col * boxSpacing;
        final y = gridStartY + row * boxSpacing;

        final isActive = (row == 0 && col == 3);
        final boxPaint = Paint()
          ..style = PaintingStyle.fill;

        if (isActive) {
          boxPaint.shader = brandGradient.createShader(
            Rect.fromLTWH(x, y, boxSize, boxSize),
          );
        } else {
          boxPaint.color = const Color(0xFFD1D5DB);
        }

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, boxSize, boxSize),
            Radius.circular(w * 0.01),
          ),
          boxPaint,
        );
      }
    }

    // 5. Pulse Waveform (SVG path with stroke)
    final pulsePath = Path();
    pulsePath.moveTo(innerOffset.dx + innerW * 0.1, center.dy);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.24, center.dy);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.32, center.dy - h * 0.20);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.44, center.dy + h * 0.25);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.56, center.dy - h * 0.20);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.64, center.dy + h * 0.12);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.85, center.dy);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..shader = brandGradient.createShader(
        Rect.fromLTWH(0, 0, w, h),
      )
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(pulsePath, pulsePaint);

    // 6. Pulse Dot (SVG: circle at end)
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = brandGradient.createShader(
        Rect.fromCircle(center: center, radius: w * 0.05),
      );

    canvas.drawCircle(Offset(innerOffset.dx + innerW * 0.85, center.dy), w * 0.04, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
