import 'package:flutter/material.dart';

import '../models/skin_analysis.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';

/// Résultat de l'analyse de peau : type, conditions, produits, disclaimer.
class SkinResultScreen extends StatelessWidget {
  final SkinAnalysisResult result;
  final VoidCallback onRetry;

  const SkinResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  static const _skinTypeLabels = {
    'oily': 'Grasse',
    'dry': 'Sèche',
    'combination': 'Mixte',
    'normal': 'Normale',
  };

  static const _severityLabels = {
    'mild': 'Faible',
    'moderate': 'Modérée',
    'severe': 'Marquée',
  };

  Color _severityColor(int score) {
    if (score >= 60) return AppColors.negative;
    if (score >= 30) return Colors.orange;
    return AppColors.positive;
  }

  @override
  Widget build(BuildContext context) {
    // On ne met en avant que les conditions au-dessus du seuil de recommandation.
    final visibles = result.conditions.where((c) => c.score >= 30).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: 'Diagnostic de peau'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (result.age != null) ...[
                    _buildAgeCard(context),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _buildSkinTypeCard(context),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Conditions détectées',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (visibles.isEmpty)
                    const CustomCard(
                      child: Text('Aucune condition marquée détectée.'),
                    )
                  else
                    ...visibles.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildConditionTile(context, c),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Produits recommandés',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (result.recommendations.isEmpty)
                    const CustomCard(
                      child: Text('Aucun produit correspondant en stock.'),
                    )
                  else
                    ...result.recommendations.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildRecommendationTile(context, r),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildDisclaimer(context),
                  const SizedBox(height: AppSpacing.lg),
                  CustomButton(
                    label: 'Refaire la capture',
                    icon: Icons.refresh,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkinTypeCard(BuildContext context) {
    final label = _skinTypeLabels[result.skinType] ?? result.skinType;
    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.water_drop_outlined,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type de peau',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgeCard(BuildContext context) {
    final age = result.age!;
    final details = StringBuffer('Estimation : ${age.estimatedAge} ans');
    if (age.realAge != null) {
      details.write(' · Âge réel : ${age.realAge} ans');
    }
    return CustomCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.cake_outlined,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Âge de la peau',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  age.messageFr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConditionTile(BuildContext context, SkinCondition condition) {
    final color = _severityColor(condition.score);
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  condition.labelFr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _severityLabels[condition.severity] ?? condition.severity,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: condition.score / 100,
              minHeight: 8,
              color: color,
              backgroundColor: AppColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationTile(
      BuildContext context, ProductRecommendation reco) {
    return CustomCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SizedBox(
              width: 56,
              height: 56,
              child: reco.imageUrl == null
                  ? Container(
                      color: AppColors.primaryLight,
                      child: const Icon(Icons.spa_outlined,
                          color: AppColors.primary),
                    )
                  : Image.network(
                      reco.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primaryLight,
                        child: const Icon(Icons.spa_outlined,
                            color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reco.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reco.brand != null)
                  Text(reco.brand!,
                      style: Theme.of(context).textTheme.bodySmall),
                if (reco.price != null)
                  Text(
                    '${reco.price!.toStringAsFixed(2)} DT',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  reco.reasonFr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              result.disclaimerFr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
