import 'dart:io';

import 'package:flutter/material.dart';

import '../models/skin_analysis.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';
import 'skin_result/condition_card.dart';
import 'skin_result/detailed_report.dart';
import 'skin_result/diagnostic_hero.dart';
import 'skin_result/observation_card.dart';
import 'skin_result/product_detail_sheet.dart';
import 'skin_result/product_filter_bar.dart';
import 'skin_result/routine_placeholder.dart';
import 'skin_result/skin_derivations.dart';

/// Diagnostic de peau — style Clinique premium, valeurs dérivées du résultat réel.
class SkinResultScreen extends StatefulWidget {
  final SkinAnalysisResult result;
  final VoidCallback onRetry;
  final File? frontPhoto;

  const SkinResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
    this.frontPhoto,
  });

  @override
  State<SkinResultScreen> createState() => _SkinResultScreenState();
}

class _SkinResultScreenState extends State<SkinResultScreen> {
  static const _skinTypeLabels = {
    'oily': 'Grasse',
    'dry': 'Sèche',
    'combination': 'Mixte',
    'normal': 'Normale',
  };

  FilterState _filter = const FilterState();
  final Set<String> _expanded = {};
  bool _filterExpanded = false;
  bool _reportExpanded = false;

  void _stub(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, String> get _labelByCode =>
      {for (final c in widget.result.conditions) c.code: c.labelFr};

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final flagged = flaggedCodes(result.conditions);
    final priorities = priorityConditions(result.conditions);
    final gScore = globalScore(result.conditions);
    final brands = brandsInResults(result.recommendations);

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
                  DiagnosticHero(
                    frontPhoto: widget.frontPhoto,
                    skinTypeLabel:
                        _skinTypeLabels[result.skinType] ?? result.skinType,
                    globalScore: gScore,
                    globalLabel: gScore == null ? null : globalLabel(gScore),
                    estimatedAge: result.age?.estimatedAge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ObservationCard(
                      observation: deriveObservation(result.conditions)),
                  const SizedBox(height: AppSpacing.md),
                  ProductFilterBar(
                    expanded: _filterExpanded,
                    onToggleExpanded: () => setState(
                        () => _filterExpanded = !_filterExpanded),
                    filter: _filter,
                    catalog: brands,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (priorities.isEmpty) ...[
                    _healthyState(context),
                    const SizedBox(height: AppSpacing.md),
                  ] else
                    ...priorities.map((c) {
                      final views = productViewsForCondition(
                        code: c.code,
                        recs: result.recommendations,
                        flagged: flagged,
                        filter: _filter,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ConditionCard(
                          condition: c,
                          health: healthScore(c),
                          severity: severityBand(c.score),
                          expanded: _expanded.contains(c.code),
                          onToggle: () => setState(() {
                            if (_expanded.contains(c.code)) {
                              _expanded.remove(c.code);
                            } else {
                              _expanded.add(c.code);
                            }
                          }),
                          products: views,
                          onProductTap: (v) => ProductDetailSheet.show(
                            context,
                            view: v,
                            matchedLabels: [
                              for (final code in v.product.matchedConditions)
                                _labelByCode[code] ?? code,
                            ],
                            onAdd: () => _stub('Bientôt : ajout au panier'),
                          ),
                          onProductAdd: (_) =>
                              _stub('Bientôt : ajout au panier'),
                        ),
                      );
                    }),
                  DetailedReport(
                    conditions: result.conditions,
                    expanded: _reportExpanded,
                    onToggle: () =>
                        setState(() => _reportExpanded = !_reportExpanded),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RoutinePlaceholder(
                    onCreate: () => _stub('Bientôt : création de routine'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (result.disclaimerFr.isNotEmpty)
                    Text(
                      result.disclaimerFr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  CustomButton(
                    label: 'Refaire la capture',
                    icon: Icons.refresh,
                    onPressed: widget.onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _healthyState(BuildContext context) {
    return CustomCard(
      child: Row(
        children: [
          const Icon(Icons.verified_outlined,
              color: AppColors.positive, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Peau globalement saine — aucune préoccupation prioritaire détectée.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
