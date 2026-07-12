import 'package:flutter/material.dart';

import '../../models/skin_analysis.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'product_card.dart';
import 'severity_style.dart';
import 'skin_derivations.dart';

/// Carte d'une condition prioritaire : score santé, sévérité, révélation produits.
class ConditionCard extends StatelessWidget {
  final SkinCondition condition;
  final int health;
  final Severity severity;
  final bool expanded;
  final VoidCallback onToggle;
  final List<ProductView> products;
  final void Function(ProductView) onProductTap;
  final void Function(ProductView) onProductAdd;

  const ConditionCard({
    super.key,
    required this.condition,
    required this.health,
    required this.severity,
    required this.expanded,
    required this.onToggle,
    required this.products,
    required this.onProductTap,
    required this.onProductAdd,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: severityBg(severity),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Priorité ${severityLabel(severity)}',
                  style: TextStyle(
                    color: severityColor(severity),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$health/100',
                style: TextStyle(
                  color: severityColor(severity),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            condition.labelFr,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: health / 100,
              minHeight: 8,
              color: severityColor(severity),
              backgroundColor: AppColors.divider,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: onToggle,
              child: Text(
                  expanded ? 'Masquer les produits' : 'Trouver des produits'),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            if (products.isEmpty)
              Text('Aucun produit correspondant en stock.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...products.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ProductCard(
                    view: v,
                    onTap: () => onProductTap(v),
                    onAdd: () => onProductAdd(v),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
