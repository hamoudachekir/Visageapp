import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'product_card.dart' show productThumb;
import 'skin_derivations.dart';

/// Fiche détaillée produit (bottom sheet) : image, prix, match %, motifs.
class ProductDetailSheet extends StatelessWidget {
  final ProductView view;
  final List<String> matchedLabels;
  final VoidCallback onAdd;

  const ProductDetailSheet({
    super.key,
    required this.view,
    required this.matchedLabels,
    required this.onAdd,
  });

  static Future<void> show(
    BuildContext context, {
    required ProductView view,
    required List<String> matchedLabels,
    required VoidCallback onAdd,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductDetailSheet(
        view: view,
        matchedLabels: matchedLabels,
        onAdd: onAdd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = view.product;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: productThumb(p.imageUrl, 120)),
          const SizedBox(height: AppSpacing.md),
          Text(
            p.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (p.brand != null)
            Text(p.brand!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (p.price != null)
                Text(
                  '${p.price!.toStringAsFixed(3)} TND',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.positiveLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${view.matchPercent}% Match',
                    style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (matchedLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final label in matchedLabels)
                  Chip(
                    label: Text(label),
                    backgroundColor: AppColors.primaryLight,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Pourquoi ce produit',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(p.reasonFr,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('Ajouter'),
            ),
          ),
        ],
      ),
    );
  }
}
