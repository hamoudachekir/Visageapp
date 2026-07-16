import 'package:flutter/material.dart';

import '../services/analysis_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';

/// Affiche le résultat de l'analyse : sexe + âge estimé (thème clair Lumina).
class ResultScreen extends StatelessWidget {
  final AnalysisResult result;
  final VoidCallback onRetry;

  const ResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: 'Diagnostic'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: result.ok ? _buildSuccess(context) : _buildFailure(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final sexe = result.sexe ?? '—';
    final age = result.ageEstime?.toString() ?? '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.positiveLight,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppColors.positive, size: 46),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Votre diagnostic',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        _InfoCard(
          icon: sexe == 'Homme' ? Icons.male : Icons.female,
          label: 'Sexe',
          value: sexe,
        ),
        const SizedBox(height: AppSpacing.sm),
        _InfoCard(
          icon: Icons.cake_outlined,
          label: 'Âge estimé',
          value: '$age ans',
        ),
        if (result.confiance != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Confiance de détection : ${(result.confiance! * 100).toStringAsFixed(0)} %',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CustomButton(
          label: 'Refaire la capture',
          icon: Icons.refresh,
          onPressed: onRetry,
        ),
      ],
    );
  }

  Widget _buildFailure(BuildContext context) {
    final raison = result.raison == 'aucun_visage_detecte'
        ? "Aucun visage n'a été détecté sur la photo de face."
        : "L'analyse a échoué (${result.raison ?? 'raison inconnue'}).";
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.negativeLight,
          ),
          child: const Icon(Icons.error_outline,
              color: AppColors.negative, size: 46),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          raison,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        CustomButton(
          label: 'Refaire la capture',
          icon: Icons.refresh,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
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
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                value,
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
}
