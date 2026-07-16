import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Transforme les coordonnées renvoyées par ML Kit vers les coordonnées
/// d'affichage du widget (overlay AR).
///
/// Trois corrections à appliquer, dans cet ordre :
///
/// 1. **Rotation** — ML Kit renvoie les coordonnées dans l'espace de l'image
///    *redressée* (après application de la rotation passée dans les métadonnées).
///    En rotation 90°/270°, l'image redressée a donc ses dimensions inversées
///    par rapport au buffer brut : sa largeur = `imageSize.height` et sa
///    hauteur = `imageSize.width`. On calcule `_srcW`/`_srcH` en conséquence.
///
/// 2. **Mise à l'échelle BoxFit.cover** — l'aperçu (`_CoverPreview`) couvre tout
///    l'écran en rognant les débordements. On reproduit exactement ce recadrage :
///    facteur = `max(largeurEcran/_srcW, hauteurEcran/_srcH)`, puis centrage.
///    Un simple ratio largeur/largeur (BoxFit.fill) décalerait les zones car
///    l'aperçu est rogné, pas étiré.
///
/// 3. **Miroir caméra frontale** — l'aperçu de la caméra avant est affiché en
///    miroir (effet « selfie »). On inverse donc X : `x → largeurEcran - x`.
class FaceOverlayMapper {
  /// Taille brute du buffer caméra (`image.width` x `image.height`).
  final Size imageSize;

  /// Rotation appliquée à l'image pour ML Kit.
  final InputImageRotation rotation;

  /// Taille du widget overlay (= l'écran, l'aperçu étant plein cadre).
  final Size canvasSize;

  /// `true` pour la caméra frontale (aperçu en miroir horizontal).
  final bool mirror;

  late final double _srcW;
  late final double _srcH;
  late final double _scale;
  late final double _offX;
  late final double _offY;

  FaceOverlayMapper({
    required this.imageSize,
    required this.rotation,
    required this.canvasSize,
    required this.mirror,
  }) {
    final rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;

    // (1) Dimensions de l'image redressée.
    _srcW = rotated ? imageSize.height : imageSize.width;
    _srcH = rotated ? imageSize.width : imageSize.height;

    // (2) Échelle « cover » + centrage (les débordements sont rognés).
    _scale = math.max(canvasSize.width / _srcW, canvasSize.height / _srcH);
    _offX = (canvasSize.width - _srcW * _scale) / 2;
    _offY = (canvasSize.height - _srcH * _scale) / 2;
  }

  /// Mappe un point de l'image redressée vers les coordonnées du widget.
  Offset mapPoint(double x, double y) {
    var dx = _offX + x * _scale;
    final dy = _offY + y * _scale;
    if (mirror) dx = canvasSize.width - dx; // (3) miroir frontal
    return Offset(dx, dy);
  }

  /// Mappe un rectangle (ex. `face.boundingBox`) ; on remappe deux coins et on
  /// renormalise car le miroir peut inverser gauche/droite.
  Rect mapRect(Rect r) {
    final a = mapPoint(r.left, r.top);
    final b = mapPoint(r.right, r.bottom);
    return Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    );
  }
}
