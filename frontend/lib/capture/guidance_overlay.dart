import 'package:flutter/material.dart';

/// Cadre de guidage superposé à l'aperçu caméra.
/// Rouge quand la position n'est pas conforme, vert quand elle l'est.
class GuidanceOverlay extends StatelessWidget {
  final bool conforme;
  final bool isTopView;

  const GuidanceOverlay({
    super.key,
    required this.conforme,
    this.isTopView = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GuidancePainter(conforme: conforme, isTopView: isTopView),
      ),
    );
  }
}

class _GuidancePainter extends CustomPainter {
  final bool conforme;
  final bool isTopView;

  _GuidancePainter({required this.conforme, required this.isTopView});

  static const _vert = Color(0xFF2ECC71);
  static const _rouge = Color(0xFFE74C3C);

  @override
  void paint(Canvas canvas, Size size) {
    final color = conforme ? _vert : _rouge;
    final guideRect = _guideRect(size);
    // Cadre ovale pour le visage, rectangle arrondi plus large pour le dessus.
    final radius = Radius.circular(isTopView ? 32 : 180);
    final rrect = RRect.fromRectAndRadius(guideRect, radius);

    // Assombrir tout ce qui est hors du cadre.
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.45);
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      overlayPaint,
    );

    // Bordure colorée.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = color;
    canvas.drawRRect(rrect, border);
  }

  Rect _guideRect(Size size) {
    final w = size.width * (isTopView ? 0.82 : 0.72);
    final h = size.height * (isTopView ? 0.55 : 0.5);
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2.4;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  bool shouldRepaint(covariant _GuidancePainter old) =>
      old.conforme != conforme || old.isTopView != isTopView;
}
