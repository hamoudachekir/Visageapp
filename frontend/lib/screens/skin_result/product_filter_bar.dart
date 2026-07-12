import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Panneau repliable de tri + priorité de marques pour les produits.
class ProductFilterBar extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final FilterState filter;
  final List<String> brands;
  final ValueChanged<FilterState> onChanged;

  const ProductFilterBar({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.filter,
    required this.brands,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Filtrer et trier les produits',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: AppSpacing.lg),
            Text('Trier par', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            DropdownButton<SortBy>(
              value: filter.sortBy,
              isExpanded: true,
              onChanged: (v) =>
                  onChanged(filter.copyWith(sortBy: v ?? filter.sortBy)),
              items: const [
                DropdownMenuItem(value: SortBy.score, child: Text('Score')),
                DropdownMenuItem(
                    value: SortBy.displayOrder,
                    child: Text("Ordre d'affichage")),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _dirButton(
                    'Décroissant',
                    filter.sortDir == SortDir.desc,
                    () => onChanged(filter.copyWith(sortDir: SortDir.desc)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _dirButton(
                    'Croissant',
                    filter.sortDir == SortDir.asc,
                    () => onChanged(filter.copyWith(sortDir: SortDir.asc)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(child: Text('Utiliser toutes les marques')),
                Switch(
                  value: filter.useAllBrands,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => onChanged(filter.copyWith(
                    useAllBrands: v,
                    priorityBrands: v ? const [] : filter.priorityBrands,
                  )),
                ),
              ],
            ),
            if (!filter.useAllBrands)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final b in brands)
                    FilterChip(
                      label: Text(b),
                      selected: filter.priorityBrands.contains(b),
                      selectedColor: AppColors.primaryLight,
                      onSelected: (sel) {
                        final next = [...filter.priorityBrands];
                        if (sel) {
                          next.add(b);
                        } else {
                          next.remove(b);
                        }
                        onChanged(filter.copyWith(priorityBrands: next));
                      },
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _dirButton(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primaryLight : null,
        side: BorderSide(
            color: selected ? AppColors.primary : AppColors.divider),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? AppColors.primaryDark : AppColors.textSecondary)),
    );
  }
}
