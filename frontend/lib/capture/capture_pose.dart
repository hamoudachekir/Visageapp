import 'package:flutter/material.dart';

/// Les 4 vues à capturer, dans l'ordre : face, profils, puis gros plan du front.
enum CapturePose { face, profilGauche, profilDroit, front }

/// Libellé court utilisé dans les vignettes (capture, validation).
String shortPoseLabel(CapturePose pose) {
  switch (pose) {
    case CapturePose.face:
      return 'Face';
    case CapturePose.profilGauche:
      return 'Profil G.';
    case CapturePose.profilDroit:
      return 'Profil D.';
    case CapturePose.front:
      return 'Front';
  }
}

/// Configuration d'une vue : libellé, instruction, icône et seuils de pose.
class PoseConfig {
  final CapturePose pose;
  final String label; // ex. "Vue de face"
  final String instruction; // ex. "Regardez droit vers la caméra"
  final IconData icon;

  // Seuils sur les angles d'Euler de la tête (degrés). null = non contraint.
  final double? yawMin; // rotation gauche/droite (headEulerAngleY)
  final double? yawMax;
  final double pitchTol; // tolérance haut/bas (headEulerAngleX)
  final double rollTol; // tolérance inclinaison (headEulerAngleZ)

  // Taille relative du visage (surface bbox / surface image) -> proxy de distance.
  final double minFaceRatio;
  final double maxFaceRatio;

  // Cette vue exige-t-elle un visage détecté ?
  final bool requiresFace;

  const PoseConfig({
    required this.pose,
    required this.label,
    required this.instruction,
    required this.icon,
    this.yawMin,
    this.yawMax,
    this.pitchTol = 14,
    this.rollTol = 14,
    this.minFaceRatio = 0.06,
    this.maxFaceRatio = 0.55,
    this.requiresFace = true,
  });
}

/// ⚠️ IMPORTANT : les SIGNES du yaw dépendent de l'appareil et de la caméra
/// (frontale = image miroir). Vérifie/inverse `yawMin`/`yawMax` des profils
/// lors des premiers tests sur un device réel.
const List<PoseConfig> kCaptureFlow = [
  PoseConfig(
    pose: CapturePose.face,
    label: 'Vue de face',
    instruction: 'Regardez droit vers la caméra, visage centré',
    icon: Icons.face,
    yawMin: -12,
    yawMax: 12,
  ),
  PoseConfig(
    pose: CapturePose.profilGauche,
    label: 'Profil gauche (45°)',
    instruction: 'Tournez la tête de 45° vers la gauche',
    icon: Icons.turn_left,
    yawMin: 30,
    yawMax: 58,
  ),
  PoseConfig(
    pose: CapturePose.profilDroit,
    label: 'Profil droit (45°)',
    instruction: 'Tournez la tête de 45° vers la droite',
    icon: Icons.turn_right,
    yawMin: -58,
    yawMax: -30,
  ),
  // Gros plan du front : visage droit mais TRÈS rapproché (minFaceRatio élevé),
  // pour capturer le détail de la peau du front. Tolérance pitch large car on
  // penche souvent un peu la tête pour présenter le front.
  PoseConfig(
    pose: CapturePose.front,
    label: 'Vue du front (gros plan)',
    instruction: 'Rapprochez le visage de la caméra pour cadrer le front',
    icon: Icons.center_focus_strong,
    yawMin: -14,
    yawMax: 14,
    pitchTol: 22,
    minFaceRatio: 0.22,
    maxFaceRatio: 0.9,
  ),
];
