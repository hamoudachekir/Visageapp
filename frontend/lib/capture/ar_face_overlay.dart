import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_overlay_mapper.dart';

/// Overlay AR « miroir magique » : effet cosmétique (PAS d'analyse réelle)
/// superposé à l'aperçu caméra pendant la capture. Dessine, ancrées au visage
/// détecté : des zones colorées pulsantes (front, joues, menton, sous-yeux,
/// zone T), une ligne de scan teal qui balaie le visage, et des libellés
/// d'« analyse » en français qui défilent.
///
/// Les zones sont positionnées en relatif dans la boîte englobante du visage
/// (`face.boundingBox`) plutôt que sur des landmarks ML Kit précis : c'est
/// volontairement robuste (pas besoin d'activer contours/landmarks, donc aucun
/// surcoût de détection sur le flux de capture réel) et tolérant aux petites
/// imprécisions de rotation/miroir selon l'appareil.
///
/// Un fondu doux (entrée/sortie, ~350 ms) évite l'apparition brutale de
/// l'overlay quand un visage entre ou sort du cadre.
class ArFaceOverlay extends StatefulWidget {
  final Face? face;
  final Size? imageSize;
  final InputImageRotation? rotation;

  /// `true` pour la caméra frontale (aperçu en miroir).
  final bool mirror;

  const ArFaceOverlay({
    super.key,
    required this.face,
    required this.imageSize,
    required this.rotation,
    required this.mirror,
  });

  @override
  State<ArFaceOverlay> createState() => _ArFaceOverlayState();
}

class _ArFaceOverlayState extends State<ArFaceOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _anim; // animation continue (pulse/scan/blink)
  late final AnimationController _fade; // fondu entrée/sortie
  Timer? _labelTimer;
  int _labelIndex = 0;

  // Dernier visage affichable, conservé pendant le fondu de sortie pour éviter
  // que l'overlay ne disparaisse d'un coup quand le visage est perdu.
  Face? _displayFace;
  Size? _displayImageSize;
  InputImageRotation? _displayRotation;

  static const _labels = [
    "Analyse de l'hydratation…",
    'Détection des zones de rougeur…',
    'Cartographie du teint…',
    'Évaluation de la texture…',
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    // Une fois le fondu de sortie terminé, on libère le visage conservé.
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() {
          _displayFace = null;
          _displayImageSize = null;
          _displayRotation = null;
        });
      }
    });
    _syncFace();
    _labelTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (mounted) setState(() => _labelIndex = (_labelIndex + 1) % _labels.length);
    });
  }

  @override
  void didUpdateWidget(covariant ArFaceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFace();
  }

  /// Met à jour le visage affiché et déclenche le fondu d'entrée ou de sortie.
  void _syncFace() {
    final present = widget.face != null &&
        widget.imageSize != null &&
        widget.rotation != null;
    if (present) {
      _displayFace = widget.face;
      _displayImageSize = widget.imageSize;
      _displayRotation = widget.rotation;
      if (_fade.status != AnimationStatus.completed &&
          _fade.status != AnimationStatus.forward) {
        _fade.forward();
      }
    } else {
      if (_fade.status != AnimationStatus.dismissed &&
          _fade.status != AnimationStatus.reverse) {
        _fade.reverse();
      }
    }
  }

  @override
  void dispose() {
    _labelTimer?.cancel();
    _anim.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = _displayFace;
    final imageSize = _displayImageSize;
    final rotation = _displayRotation;
    // Rien à dessiner tant qu'aucun visage (et fondu de sortie terminé).
    if (face == null || imageSize == null || rotation == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_anim, _fade]),
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _ArPainter(
              boundingBox: face.boundingBox,
              imageSize: imageSize,
              rotation: rotation,
              mirror: widget.mirror,
              t: _anim.value,
              label: _labels[_labelIndex],
              opacity: Curves.easeOut.transform(_fade.value),
            ),
          );
        },
      ),
    );
  }
}

class _ArZone {
  final double fx; // centre relatif X dans la boîte (0..1)
  final double fy; // centre relatif Y dans la boîte (0..1)
  final double fr; // rayon relatif à la largeur de la boîte
  final Color color;
  final double phase; // déphasage de pulsation
  const _ArZone(this.fx, this.fy, this.fr, this.color, this.phase);
}

class _ArPainter extends CustomPainter {
  final Rect boundingBox;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool mirror;
  final double t; // 0..1, phase d'animation
  final String label;
  final double opacity; // 0..1, fondu d'ensemble

  _ArPainter({
    required this.boundingBox,
    required this.imageSize,
    required this.rotation,
    required this.mirror,
    required this.t,
    required this.label,
    required this.opacity,
  });

  // Palette « Clinical Spa ».
  static const _teal = Color(0xFF0C7C84);
  static const _coral = Color(0xFFFF8A75);
  static const _sage = Color(0xFF7FB89E);
  static const _rose = Color(0xFFD88B8B);

  static const _zones = [
    _ArZone(0.50, 0.13, 0.14, _teal, 0.0), // front
    _ArZone(0.26, 0.56, 0.12, _coral, 0.6), // joue gauche
    _ArZone(0.74, 0.56, 0.12, _coral, 0.6), // joue droite
    _ArZone(0.34, 0.42, 0.07, _rose, 1.2), // sous-yeux gauche
    _ArZone(0.66, 0.42, 0.07, _rose, 1.2), // sous-yeux droit
    _ArZone(0.50, 0.47, 0.08, _sage, 1.8), // zone T (nez)
    _ArZone(0.50, 0.92, 0.09, _sage, 2.4), // menton
  ];

  /// Applique le fondu d'ensemble à une valeur d'alpha (0..255).
  int _alpha(num base) => (base * opacity).clamp(0, 255).round();

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final mapper = FaceOverlayMapper(
      imageSize: imageSize,
      rotation: rotation,
      canvasSize: size,
      mirror: mirror,
    );
    final box = mapper.mapRect(boundingBox);
    if (box.isEmpty || box.width < 8 || box.height < 8) return;

    _paintZones(canvas, box);
    _paintScanLine(canvas, box);
    _paintLabel(canvas, box, size.width);
  }

  void _paintZones(Canvas canvas, Rect box) {
    for (final z in _zones) {
      // Pulsation : rayon et opacité oscillent, déphasés par zone.
      final pulse = 0.5 + 0.5 * math.sin((t * 2 * math.pi * 2) + z.phase);
      final center = Offset(
        box.left + z.fx * box.width,
        box.top + z.fy * box.height,
      );
      final r = z.fr * box.width * (0.85 + 0.30 * pulse);

      // Halo flou.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = z.color.withAlpha(_alpha(70 * (0.6 + 0.4 * pulse)))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
      );
      // Anneau fin.
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = z.color.withAlpha(_alpha(150 * (0.5 + 0.5 * pulse))),
      );
      // Cœur lumineux.
      canvas.drawCircle(
        center,
        r * 0.16,
        Paint()..color = z.color.withAlpha(_alpha(230)),
      );
    }
  }

  void _paintScanLine(Canvas canvas, Rect box) {
    // Va-et-vient vertical (ping-pong) sur la hauteur du visage.
    final pingPong = t < 0.5 ? t * 2 : (1 - t) * 2;
    final y = box.top + box.height * pingPong;
    final bandH = box.height * 0.10;

    canvas.save();
    // On confine le balayage au visage (rectangle arrondi type ovale).
    final clip = RRect.fromRectAndRadius(
      box.deflate(box.width * 0.02),
      Radius.circular(box.width * 0.5),
    );
    canvas.clipRRect(clip);

    // Bande dégradée autour de la ligne.
    final bandRect = Rect.fromLTRB(box.left, y - bandH, box.right, y + bandH);
    canvas.drawRect(
      bandRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _teal.withAlpha(0),
            _teal.withAlpha(_alpha(77)),
            _teal.withAlpha(0),
          ],
        ).createShader(bandRect),
    );
    // Ligne nette.
    canvas.drawLine(
      Offset(box.left, y),
      Offset(box.right, y),
      Paint()
        ..color = _teal.withAlpha(_alpha(220))
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();
  }

  void _paintLabel(Canvas canvas, Rect box, double canvasW) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: GoogleFonts.robotoMono(
          color: Colors.white.withAlpha(_alpha(255)),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);

    const padH = 10.0;
    const padV = 6.0;
    final chipW = tp.width + padH * 2;
    final chipH = tp.height + padV * 2;
    // Au-dessus de la boîte, centré, en restant dans l'écran.
    final cx = box.center.dx.clamp(chipW / 2 + 8, canvasW - chipW / 2 - 8);
    final top = math.max(8.0, box.top - chipH - 10);
    final chipRect = Rect.fromLTWH(cx - chipW / 2, top, chipW, chipH);

    final rr = RRect.fromRectAndRadius(chipRect, const Radius.circular(999));
    canvas.drawRRect(rr, Paint()..color = Colors.black.withAlpha(_alpha(140)));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _teal.withAlpha(_alpha(160)),
    );
    // Petit point clignotant en tête de libellé.
    final blink = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 3);
    canvas.drawCircle(
      Offset(chipRect.left + padH, chipRect.center.dy),
      2.5,
      Paint()..color = _coral.withAlpha(_alpha(255 * blink)),
    );
    tp.paint(canvas, Offset(chipRect.left + padH + 8, chipRect.top + padV));
  }

  @override
  bool shouldRepaint(covariant _ArPainter old) =>
      old.t != t ||
      old.opacity != opacity ||
      old.label != label ||
      old.boundingBox != boundingBox;
}
