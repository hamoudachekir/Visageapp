import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// En-tête du diagnostic : photo, type de peau, anneau de score global, âge.
class DiagnosticHero extends StatelessWidget {
  final File? frontPhoto;
  final String skinTypeLabel;
  final int? globalScore;
  final String? globalLabel;
  final int? estimatedAge;

  const DiagnosticHero({
    super.key,
    this.frontPhoto,
    required this.skinTypeLabel,
    this.globalScore,
    this.globalLabel,
    this.estimatedAge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _photo(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Votre type de peau',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      skinTypeLabel,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _scoreRing(context),
          if (estimatedAge != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cake_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Âge de peau estimé · $estimatedAge ans',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _photo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: SizedBox(
        width: 72,
        height: 72,
        child: frontPhoto == null
            ? Container(
                color: AppColors.surface,
                child: const Icon(Icons.face_retouching_natural,
                    color: AppColors.primary, size: 34),
              )
            : Image.file(frontPhoto!, fit: BoxFit.cover),
      ),
    );
  }

  Widget _scoreRing(BuildContext context) {
    if (globalScore == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 128,
                height: 128,
                child: CircularProgressIndicator(
                  value: globalScore! / 100,
                  strokeWidth: 10,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$globalScore',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text('/100',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        if (globalLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            globalLabel!,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
