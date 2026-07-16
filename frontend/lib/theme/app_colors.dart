import 'package:flutter/material.dart';

/// Palette "Ismouda" de l'application (teal clinique, fond bleu-blanc froid,
/// texte bleu nuit) — reprise du design system Stitch.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF0C7C84);
  static const primaryDark = Color(0xFF006168);
  static const primaryLight = Color(0xFFD8FCFF);

  static const accent = Color(0xFF13686D);

  static const background = Color(0xFFF8F9FF);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF0B1C30);
  static const textSecondary = Color(0xFF4E5A5B);

  static const positive = Color(0xFF7FB89E);
  static const negative = Color(0xFFD88B8B);
  static const success = positive;
  static const warning = negative;

  static const positiveLight = Color(0xFFEAF4EF);
  static const negativeLight = Color(0xFFFBEDED);

  static const divider = Color(0xFFD7E3E4);
  static const dividerStrong = Color(0xFFBDC9CA);
  static const disabled = Color(0xFFB7C2C3);
  static const overlay = Color(0x661A1F1F);

  /// Ombre douce standard des cartes (offset 0,2 — blur 8 — noir 5%).
  static const cardShadow = BoxShadow(
    color: Color(0x0D000000),
    offset: Offset(0, 2),
    blurRadius: 8,
  );
}
