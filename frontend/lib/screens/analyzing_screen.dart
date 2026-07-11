import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';

/// Écran affiché pendant l'appel au backend : anneau de progression
/// indéterminé + liste d'étapes (thème clair Lumina). Possède l'appel API.
/// Générique : `T` est le type de résultat renvoyé par `analyze`.
class AnalyzingScreen<T> extends StatefulWidget {
  final Future<T> Function() analyze;
  final void Function(T result) onResult;
  final VoidCallback onRetry;

  const AnalyzingScreen({
    super.key,
    required this.analyze,
    required this.onResult,
    required this.onRetry,
  });

  @override
  State<AnalyzingScreen<T>> createState() => _AnalyzingScreenState<T>();
}

class _AnalyzingScreenState<T> extends State<AnalyzingScreen<T>> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      final result = await widget.analyze();
      if (!mounted) return;
      widget.onResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: 'Analyse'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: _error != null ? _buildError() : _buildProgress(context),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 170,
                height: 170,
                child: CircularProgressIndicator(
                  strokeWidth: 8,
                  color: AppColors.primary,
                  backgroundColor: AppColors.primaryLight,
                ),
              ),
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryLight,
                ),
                child: const Center(
                  child: Icon(Icons.face_retouching_natural,
                      color: AppColors.primary, size: 36),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Analyse de votre peau…',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          "Nous analysons vos 4 photos pour évaluer votre peau.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        const SizedBox(
          width: 280,
          child: Column(
            children: [
              _StepRow(label: 'Photos importées', state: _StepState.done),
              SizedBox(height: 11),
              _StepRow(label: 'Analyse de la peau', state: _StepState.active),
              SizedBox(height: 11),
              _StepRow(label: 'Recommandations', state: _StepState.pending),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
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
          child: const Icon(Icons.wifi_off, size: 44, color: AppColors.negative),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          "Impossible de joindre le serveur d'analyse.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        CustomButton(
          label: 'Réessayer',
          icon: Icons.refresh,
          onPressed: _run,
        ),
        const SizedBox(height: AppSpacing.xs),
        CustomButton(
          label: 'Revenir à la validation',
          ghost: true,
          onPressed: widget.onRetry,
        ),
      ],
    );
  }
}

enum _StepState { done, active, pending }

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;

  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    Widget bullet;
    Color textColor;
    switch (state) {
      case _StepState.done:
        bullet = Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.positive),
          child: const Icon(Icons.check, color: Colors.white, size: 13),
        );
        textColor = AppColors.textPrimary;
        break;
      case _StepState.active:
        bullet = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.primary),
            ),
          ),
        );
        textColor = AppColors.primary;
        break;
      case _StepState.pending:
        bullet = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.dividerStrong, width: 2),
          ),
        );
        textColor = AppColors.textSecondary;
        break;
    }

    return Row(
      children: [
        bullet,
        const SizedBox(width: 11),
        Text(
          label,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }
}
