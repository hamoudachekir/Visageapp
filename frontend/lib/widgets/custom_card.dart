import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Carte blanche à coins arrondis (16px) avec ombre douce, brique de base
/// de la plupart des écrans (formulaires, résultats, etc.).
class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: child,
    );
  }
}
