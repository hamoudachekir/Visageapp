import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'capture_pose.dart';

/// Petite vignette de guidage (en haut à droite de la capture) : un visage
/// schématique dessiné, orienté selon la vue demandée, pour montrer au client
/// comment se positionner.
class PoseGuide extends StatelessWidget {
  final CapturePose pose;

  const PoseGuide({super.key, required this.pose});

  String get _label {
    switch (pose) {
      case CapturePose.face:
        return 'Face';
      case CapturePose.profilGauche:
        return 'Gauche';
      case CapturePose.profilDroit:
        return 'Droite';
      case CapturePose.front:
        return 'Gros plan';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(115),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x557BD4DD)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Position',
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Colors.white.withAlpha(160),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 50,
            height: 54,
            child: CustomPaint(painter: _PoseGuidePainter(pose)),
          ),
          const SizedBox(height: 4),
          Text(
            _label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF7BD4DD),
            ),
          ),
        ],
      ),
    );
  }
}

class _PoseGuidePainter extends CustomPainter {
  final CapturePose pose;

  _PoseGuidePainter(this.pose);

  static const _teal = Color(0xFF7BD4DD);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    final fill = Paint()..color = Colors.white.withAlpha(28);
    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _teal;
    final dot = Paint()..color = Colors.white;

    final cx = size.width / 2;
    final cy = size.height * 0.46;

    switch (pose) {
      case CapturePose.face:
        _drawFront(canvas, cx, cy, size.width * 0.30, stroke, fill, dot);
        break;
      case CapturePose.front:
        _drawFront(canvas, cx, cy, size.width * 0.38, stroke, fill, dot);
        _cropMarks(canvas, size, accent);
        break;
      case CapturePose.profilGauche:
        _drawProfile(canvas, size, stroke, fill, dot, faceLeft: true);
        _turnArrow(canvas, size, accent, left: true);
        break;
      case CapturePose.profilDroit:
        _drawProfile(canvas, size, stroke, fill, dot, faceLeft: false);
        _turnArrow(canvas, size, accent, left: false);
        break;
    }
  }

  /// Visage de face : ovale + deux yeux + nez + bouche.
  void _drawFront(Canvas canvas, double cx, double cy, double r, Paint stroke,
      Paint fill, Paint dot) {
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: r * 1.7, height: r * 2.1);
    canvas.drawOval(rect, fill);
    canvas.drawOval(rect, stroke);
    // yeux
    canvas.drawCircle(Offset(cx - r * 0.45, cy - r * 0.25), 1.8, dot);
    canvas.drawCircle(Offset(cx + r * 0.45, cy - r * 0.25), 1.8, dot);
    // nez
    canvas.drawLine(Offset(cx, cy - r * 0.05), Offset(cx, cy + r * 0.3), stroke);
    // bouche
    final mouth = Path()
      ..moveTo(cx - r * 0.35, cy + r * 0.6)
      ..quadraticBezierTo(cx, cy + r * 0.78, cx + r * 0.35, cy + r * 0.6);
    canvas.drawPath(mouth, stroke);
  }

  /// Profil : silhouette latérale (front, nez, lèvres, menton).
  void _drawProfile(
      Canvas canvas, Size size, Paint stroke, Paint fill, Paint dot,
      {required bool faceLeft}) {
    final w = size.width;
    final h = size.height;
    // Profil dessiné face à droite, puis miroir si faceLeft.
    canvas.save();
    if (faceLeft) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    final p = Path()
      ..moveTo(w * 0.30, h * 0.20) // haut du crâne
      ..quadraticBezierTo(w * 0.78, h * 0.16, w * 0.74, h * 0.42) // arrière/haut
      ..quadraticBezierTo(w * 0.72, h * 0.36, w * 0.66, h * 0.40) // front
      ..lineTo(w * 0.82, h * 0.52) // nez (pointe)
      ..lineTo(w * 0.64, h * 0.56) // sous le nez
      ..quadraticBezierTo(w * 0.70, h * 0.62, w * 0.62, h * 0.66) // lèvres
      ..quadraticBezierTo(w * 0.70, h * 0.74, w * 0.52, h * 0.80) // menton
      ..quadraticBezierTo(w * 0.30, h * 0.82, w * 0.30, h * 0.62) // mâchoire/cou
      ..quadraticBezierTo(w * 0.18, h * 0.42, w * 0.30, h * 0.20); // arrière crâne
    canvas.drawPath(p, fill);
    canvas.drawPath(p, stroke);
    // œil
    canvas.drawCircle(Offset(w * 0.52, h * 0.42), 1.8, dot);
    canvas.restore();
  }

  /// Repères d'angle autour du visage (gros plan).
  void _cropMarks(Canvas canvas, Size size, Paint accent) {
    final w = size.width;
    const m = 2.0, len = 8.0;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), accent);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), accent);
    }
    corner(m, m, 1, 1);
    corner(w - m, m, -1, 1);
  }

  /// Flèche de rotation indiquant le sens à tourner.
  void _turnArrow(Canvas canvas, Size size, Paint accent, {required bool left}) {
    final w = size.width, h = size.height;
    final y = h * 0.92;
    final path = Path()
      ..moveTo(w * 0.30, y)
      ..quadraticBezierTo(w * 0.5, y - 7, w * 0.70, y);
    canvas.drawPath(path, accent);
    final tipX = left ? w * 0.30 : w * 0.70;
    final dir = left ? 1.0 : -1.0;
    canvas.drawLine(
        Offset(tipX, y), Offset(tipX + dir * 5, y - 4), accent);
    canvas.drawLine(
        Offset(tipX, y), Offset(tipX + dir * 5, y + 4), accent);
  }

  @override
  bool shouldRepaint(covariant _PoseGuidePainter old) => old.pose != pose;
}
