import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'skin_derivations.dart';

/// Couleur d'accent d'une sévérité (pastille, texte).
Color severityColor(Severity s) {
  switch (s) {
    case Severity.faible:
      return AppColors.positive;
    case Severity.moderee:
      return const Color(0xFFE8973A);
    case Severity.marquee:
      return AppColors.negative;
  }
}

/// Couleur de fond douce d'une sévérité (pastille).
Color severityBg(Severity s) {
  switch (s) {
    case Severity.faible:
      return AppColors.positiveLight;
    case Severity.moderee:
      return const Color(0xFFFFF3E0);
    case Severity.marquee:
      return AppColors.negativeLight;
  }
}
