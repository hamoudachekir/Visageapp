import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'capture_pose.dart';

/// Résultat de l'évaluation d'une frame : conforme ou non + message d'aide.
class PoseEvaluation {
  final bool conforme;
  final String hint;
  const PoseEvaluation(this.conforme, this.hint);
}

class FacePoseValidator {
  /// Évalue les visages détectés par rapport à la vue attendue.
  /// [faces] : visages renvoyés par ML Kit.
  /// [imageSize] : taille de l'image analysée (pour le ratio de distance).
  static PoseEvaluation evaluate(
    PoseConfig cfg,
    List<Face> faces,
    Size imageSize,
  ) {
    // --- Vue du dessus : on veut justement NE PAS voir de visage frontal ---
    if (!cfg.requiresFace) {
      if (faces.isEmpty) {
        return const PoseEvaluation(true, 'Position correcte');
      }
      return const PoseEvaluation(false, 'Penchez davantage la tête en avant');
    }

    if (faces.isEmpty) {
      return const PoseEvaluation(false, 'Aucun visage détecté');
    }
    if (faces.length > 1) {
      return const PoseEvaluation(false, 'Un seul visage dans le cadre');
    }

    final face = faces.first;
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    final roll = face.headEulerAngleZ;

    // Taille relative du visage (proxy de distance)
    final ratio = (face.boundingBox.width * face.boundingBox.height) /
        (imageSize.width * imageSize.height);
    if (ratio < cfg.minFaceRatio) {
      return const PoseEvaluation(false, 'Rapprochez-vous');
    }
    if (ratio > cfg.maxFaceRatio) {
      return const PoseEvaluation(false, 'Éloignez-vous un peu');
    }

    // Inclinaison (roll)
    if (roll != null && roll.abs() > cfg.rollTol) {
      return const PoseEvaluation(false, 'Gardez la tête droite');
    }
    // Haut/bas (pitch)
    if (pitch != null && pitch.abs() > cfg.pitchTol) {
      return const PoseEvaluation(false, 'Ne penchez pas la tête');
    }

    // Rotation gauche/droite (yaw)
    if (cfg.yawMin != null && cfg.yawMax != null) {
      if (yaw == null) {
        return const PoseEvaluation(false, 'Positionnement en cours…');
      }
      if (yaw < cfg.yawMin!) {
        return PoseEvaluation(false, _yawHint(cfg, tooLow: true));
      }
      if (yaw > cfg.yawMax!) {
        return PoseEvaluation(false, _yawHint(cfg, tooLow: false));
      }
    }

    return const PoseEvaluation(true, 'Position correcte');
  }

  static String _yawHint(PoseConfig cfg, {required bool tooLow}) {
    switch (cfg.pose) {
      case CapturePose.face:
        return 'Regardez droit devant';
      case CapturePose.profilGauche:
        return tooLow ? 'Tournez plus vers la gauche' : 'Tournez un peu moins';
      case CapturePose.profilDroit:
        return tooLow ? 'Tournez un peu moins' : 'Tournez plus vers la droite';
      case CapturePose.dessus:
        return '';
    }
  }
}
