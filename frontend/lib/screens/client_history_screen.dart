import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/client_profile.dart';
import '../models/diagnostic.dart';
import '../providers/session_flow_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';
import 'questionnaire_screen.dart';

/// Fiche d'un client existant : profil + historique de ses diagnostics.
/// Affichée quand on retrouve un client par téléphone, à la place de rouvrir
/// directement le questionnaire.
class ClientHistoryScreen extends ConsumerStatefulWidget {
  final ClientProfile client;
  final List<CameraDescription> cameras;

  const ClientHistoryScreen({
    super.key,
    required this.client,
    required this.cameras,
  });

  @override
  ConsumerState<ClientHistoryScreen> createState() =>
      _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends ConsumerState<ClientHistoryScreen> {
  late Future<List<Diagnostic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(clientRepositoryProvider)
        .diagnosticsFor(widget.client.id!);
  }

  void _newAnalysis() {
    ref.read(sessionFlowProvider.notifier).setClient(widget.client);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionnaireScreen(cameras: widget.cameras),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppHeader(
        title: 'Fiche client',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileCard(client: widget.client),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Historique des diagnostics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FutureBuilder<List<Diagnostic>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          return _InfoBox(
                            icon: Icons.error_outline,
                            color: AppColors.negative,
                            text: snap.error.toString(),
                          );
                        }
                        final diags = snap.data ?? const [];
                        if (diags.isEmpty) {
                          return const _InfoBox(
                            icon: Icons.history,
                            color: AppColors.textSecondary,
                            text: 'Aucun diagnostic enregistré pour ce client.',
                          );
                        }
                        return Column(
                          children: [
                            for (final d in diags) ...[
                              _DiagnosticCard(diagnostic: d),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: CustomButton(
                label: 'Nouvelle analyse',
                icon: Icons.add,
                onPressed: _newAnalysis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final ClientProfile client;

  const _ProfileCard({required this.client});

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(client),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.nomComplet,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 2),
                _line(context, Icons.phone_outlined, client.telephone),
                if (client.email != null && client.email!.isNotEmpty)
                  _line(context, Icons.mail_outline, client.email!),
                _line(context, Icons.spa_outlined,
                    'Peau sensible : ${client.peauSensible}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(ClientProfile c) {
    final a = c.prenom.isNotEmpty ? c.prenom[0] : '';
    final b = c.nom.isNotEmpty ? c.nom[0] : '';
    return (a + b).toUpperCase();
  }
}

class _DiagnosticCard extends StatelessWidget {
  final Diagnostic diagnostic;

  const _DiagnosticCard({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                _fmtDate(diagnostic.createdAt),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(context, 'Type de peau', diagnostic.typePeau),
          _row(context, 'Tendance acnéique', diagnostic.tendanceAcneique),
          _row(context, 'Sensibilité cutanée', diagnostic.sensibiliteCutanee),
          if (diagnostic.ageEstime != null)
            _row(context, 'Analyse photo',
                '${diagnostic.ageEstime} ans · ${diagnostic.sexe ?? ""}'),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime? d) {
    if (d == null) return 'Date inconnue';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} à ${two(l.hour)}:${two(l.minute)}';
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoBox({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
