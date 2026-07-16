import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Échelle typographique "Clinical Spa" : Fraunces (display, expressive,
/// empattée) pour les titres, Inter (neutre, très lisible) pour le reste.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _fraunces({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    double? height,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: AppColors.textPrimary,
      );

  static TextStyle _inter({
    required double fontSize,
    required FontWeight fontWeight,
    double letterSpacing = 0,
    double? height,
    Color color = AppColors.textPrimary,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );

  static TextStyle get display => _fraunces(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        height: 1.1,
      );

  static TextStyle get h1 => _fraunces(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.2,
      );

  static TextStyle get h2 => _fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.25,
      );

  static TextStyle get title => _inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.3,
      );

  static TextStyle get bodyLarge => _inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => _inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => _inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle get caption => _inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: AppColors.textSecondary,
      );
}
