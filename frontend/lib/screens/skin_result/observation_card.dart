import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Synthèse dérivée : points forts (peau saine) et points à surveiller.
class ObservationCard extends StatelessWidget {
  final Observation observation;

  const ObservationCard({super.key, required this.observation});

  @override
  Widget build(BuildContext context) {
    if (observation.forts.isEmpty && observation.vigilance.isEmpty) {
      return const SizedBox.shrink();
    }
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search, color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('Observation',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          if (observation.forts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _line(
              color: AppColors.positive,
              symbol: '+',
              text: 'Points forts : ${observation.forts.join(', ')}.',
            ),
          ],
          if (observation.vigilance.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _line(
              color: AppColors.negative,
              symbol: '−',
              text: 'À surveiller : ${observation.vigilance.join(', ')}.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
      {required Color color, required String symbol, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(symbol,
            style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.textPrimary))),
      ],
    );
  }
}
