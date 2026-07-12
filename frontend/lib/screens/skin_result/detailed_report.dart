import 'package:flutter/material.dart';

import '../../models/skin_analysis.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'severity_style.dart';
import 'skin_derivations.dart';

/// Rapport détaillé repliable : tous les critères, score santé + sévérité.
class DetailedReport extends StatelessWidget {
  final List<SkinCondition> conditions;
  final bool expanded;
  final VoidCallback onToggle;

  const DetailedReport({
    super.key,
    required this.conditions,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = reportConditions(conditions);
    final n = ordered.length;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rapport détaillé',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'Évaluation basée sur $n ${n > 1 ? 'critères' : 'critère'} cutanés',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(expanded ? 'Voir moins' : 'Voir plus',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: AppSpacing.lg),
            for (final c in ordered) _row(c),
          ],
        ],
      ),
    );
  }

  Widget _row(SkinCondition c) {
    final health = healthScore(c);
    final band = severityBand(c.score);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.labelFr,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: severityBg(band),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _severityTag(band),
                  style: TextStyle(
                    color: severityColor(band),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('$health/100',
                  style: TextStyle(
                      color: severityColor(band),
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: health / 100,
              minHeight: 6,
              color: severityColor(band),
              backgroundColor: AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }

  String _severityTag(Severity s) {
    final label = severityLabel(s);
    return label[0].toUpperCase() + label.substring(1);
  }
}
