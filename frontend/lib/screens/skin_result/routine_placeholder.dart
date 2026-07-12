import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Section « Créer ma routine » — teaser Matin/Soir (développée plus tard).
class RoutinePlaceholder extends StatelessWidget {
  final VoidCallback onCreate;

  const RoutinePlaceholder({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          const Text(
            'Créer ma routine',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Matin / Soir · bientôt disponible',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
            ),
            child: const Text('Créer ma routine'),
          ),
        ],
      ),
    );
  }
}
