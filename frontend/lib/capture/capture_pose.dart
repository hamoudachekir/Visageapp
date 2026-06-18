import 'package:flutter/material.dart';

/// Les 4 vues à capturer, dans l'ordre.
enum CapturePose { face, profilGauche, profilDroit, dessus }

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

  // Cette vue exige-t-elle un visage détecté ? (false pour la vue du dessus)
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
  PoseConfig(
    pose: CapturePose.dessus,
    label: 'Vue du dessus (cheveux)',
    instruction: 'Penchez la tête en avant pour montrer le cuir chevelu',
    icon: Icons.content_cut,
    requiresFace: false,
  ),
];
