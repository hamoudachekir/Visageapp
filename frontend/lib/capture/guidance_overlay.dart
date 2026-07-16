import 'package:flutter/material.dart';

/// Cadre de guidage superposé à l'aperçu caméra (look Lumina) : ovale teal
/// type visage + équerres aux coins + croix d'alignement discrète. Vert quand
/// la position est conforme, teal pendant l'alignement.
class GuidanceOverlay extends StatelessWidget {
  final bool conforme;

  const GuidanceOverlay({super.key, required this.conforme});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GuidancePainter(conforme: conforme),
      ),
    );
  }
}

class _GuidancePainter extends CustomPainter {
  final bool conforme;

  _GuidancePainter({required this.conforme});

  static const _green = Color(0xFF2BC974);
  static const _teal = Color(0xFF7BD4DD); // primary-fixed-dim (Stitch)

  @override
  void paint(Canvas canvas, Size size) {
    final color = conforme ? _green : _teal;
    final rect = _guideRect(size);
    const cornerLength = 26.0;

    // Halo doux derrière le cadre.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = color.withAlpha(40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(rect, glow);

    // Ovale type visage.
    final oval = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withAlpha(220);
    canvas.drawOval(rect, oval);

    // Croix d'alignement discrète.
    final cross = Paint()
      ..strokeWidth = 1
      ..color = color.withAlpha(50);
    canvas.drawLine(
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
      cross,
    );
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      cross,
    );

    // Équerres aux coins du rectangle englobant.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;

    void drawCorner(Offset origin, double dx, double dy) {
      final path = Path()
        ..moveTo(origin.dx, origin.dy + dy * cornerLength)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + dx * cornerLength, origin.dy);
      canvas.drawPath(path, corner);
    }

    drawCorner(rect.topLeft, 1, 1);
    drawCorner(rect.topRight, -1, 1);
    drawCorner(rect.bottomLeft, 1, -1);
    drawCorner(rect.bottomRight, -1, -1);
  }

  Rect _guideRect(Size size) {
    final w = size.width * 0.70;
    final h = size.height * 0.52;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2.3;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  bool shouldRepaint(covariant _GuidancePainter old) =>
      old.conforme != conforme;
}
