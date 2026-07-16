import 'package:flutter/material.dart';

import '../models/client_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/custom_button.dart';

/// Écran de confirmation affiché (sur le web) après l'enregistrement du client
/// et de son diagnostic, là où le téléphone enchaînerait sur la capture photo.
class DiagnosticSavedScreen extends StatelessWidget {
  final ClientProfile client;

  const DiagnosticSavedScreen({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      color: AppColors.positiveLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: AppColors.positive, size: 46),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Profil et diagnostic enregistrés',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${client.nomComplet} · ${client.telephone}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.smartphone,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "La capture photo et l'analyse se font sur "
                            "l'application mobile. Ce client est déjà "
                            "retrouvable via « Client existant ».",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  CustomButton(
                    label: "Retour à l'accueil",
                    icon: Icons.home_outlined,
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
