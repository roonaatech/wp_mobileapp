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

    // High-vibrancy Electric Blue to Punchy Violet Gradient
    const brandGradient = LinearGradient(
      colors: [Color(0xFF2563EB), Color(0xFF4F46E5), Color(0xFF9333EA)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
    
    const calGradient = LinearGradient(
      colors: [Colors.white, Color(0xFFF8FAFC)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // 1. Outer Circle (SVG: cx=50, cy=50, r=45, strokeWidth=7.5)
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..shader = brandGradient.createShader(
        Rect.fromCircle(center: center, radius: w * 0.45),
      )
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, w * 0.45, outerPaint);

    // Scale factor for inner group (0.74)
    const scale = 0.74;
    final innerW = w * scale;
    final innerH = h * scale;
    final innerOffset = Offset(w / 2 - innerW / 2, h / 2 - innerH / 2);

    // 2. Calendar Body (SVG: rect x=22, y=25, width=56, height=50, rx=6)
    final calendarLeft = innerOffset.dx + innerW * (22 / 100);
    final calendarTop = innerOffset.dy + innerH * (25 / 100);
    final calendarWidth = innerW * (56 / 100);
    final calendarHeight = innerH * (50 / 100);

    final calendarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(calendarLeft, calendarTop, calendarWidth, calendarHeight),
      Radius.circular(w * 0.04),
    );

    final calendarPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = calGradient.createShader(
        Rect.fromLTWH(calendarLeft, calendarTop, calendarWidth, calendarHeight),
      );

    canvas.drawRRect(calendarRect, calendarPaint);

    // Calendar border - Crisp Dark Slate (#334155, strokeWidth: 3.5%)
    final calBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..color = const Color(0xFF334155);

    canvas.drawRRect(calendarRect, calBorderPaint);

    // 3. Calendar Rings (strokeWidth: 5.0%, #1E293B)
    final ringPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;

    // Left ring (M35 18 v11)
    final ring1X = innerOffset.dx + innerW * (35 / 100);
    final ring1Y1 = innerOffset.dy + innerH * (18 / 100);
    final ring1Y2 = ring1Y1 + innerH * 0.11;
    canvas.drawLine(Offset(ring1X, ring1Y1), Offset(ring1X, ring1Y2), ringPaint);

    // Right ring (M65 18 v11)
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
        final boxPaint = Paint()..style = PaintingStyle.fill;

        if (isActive) {
          boxPaint.shader = brandGradient.createShader(
            Rect.fromLTWH(x, y, boxSize, boxSize),
          );
        } else {
          boxPaint.color = const Color(0xFF94A3B8);
        }

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, boxSize, boxSize),
            Radius.circular(w * 0.015),
          ),
          boxPaint,
        );
      }
    }

    // 5. Pulse Waveform (SVG: M10 50 H23 L32 18 L44 85 L56 24 L65 58 H85, strokeWidth: 7.5%)
    final pulsePath = Path();
    pulsePath.moveTo(innerOffset.dx + innerW * 0.10, center.dy);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.23, center.dy);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.32, center.dy - h * 0.22);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.44, center.dy + h * 0.26);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.56, center.dy - h * 0.20);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.65, center.dy + h * 0.10);
    pulsePath.lineTo(innerOffset.dx + innerW * 0.85, center.dy);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..shader = brandGradient.createShader(
        Rect.fromLTWH(0, 0, w, h),
      )
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(pulsePath, pulsePaint);

    // 6. Pulse Dot (circle at 85, 50, radius 5.5%)
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = brandGradient.createShader(
        Rect.fromCircle(center: center, radius: w * 0.055),
      );

    canvas.drawCircle(Offset(innerOffset.dx + innerW * 0.85, center.dy), w * 0.055, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
