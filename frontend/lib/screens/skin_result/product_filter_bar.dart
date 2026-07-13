import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Panneau repliable : tri + catalogue de marques (recherche, priorité, ordre).
class ProductFilterBar extends StatefulWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final FilterState filter;
  final List<String> catalog;
  final ValueChanged<FilterState> onChanged;

  const ProductFilterBar({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.filter,
    required this.catalog,
    required this.onChanged,
  });

  @override
  State<ProductFilterBar> createState() => _ProductFilterBarState();
}

class _ProductFilterBarState extends State<ProductFilterBar> {
  String _search = '';

  FilterState get _filter => widget.filter;
  void _emit(FilterState f) => widget.onChanged(f);

  void _addBrand(String brand) {
    if (_filter.priorityBrands.contains(brand)) return;
    _emit(_filter.copyWith(
      priorityBrands: [..._filter.priorityBrands, brand],
      useAllBrands: false,
    ));
  }

  void _removeBrand(String brand) {
    _emit(_filter.copyWith(
        priorityBrands: [..._filter.priorityBrands]..remove(brand)));
  }

  void _clearBrands() =>
      _emit(_filter.copyWith(priorityBrands: const [], useAllBrands: true));

  void _move(int index, int delta) {
    final next = [..._filter.priorityBrands];
    final target = index + delta;
    if (target < 0 || target >= next.length) return;
    next.insert(target, next.removeAt(index));
    _emit(_filter.copyWith(priorityBrands: next));
  }

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onToggleExpanded,
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text('Filtrer et trier les produits',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                ),
                Icon(widget.expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
          if (widget.expanded) ...[
            const Divider(height: AppSpacing.lg),
            _sortSection(context),
            const SizedBox(height: AppSpacing.md),
            _brandSection(context),
          ],
        ],
      ),
    );
  }

  Widget _sortSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trier les produits par',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        DropdownButton<SortBy>(
          value: _filter.sortBy,
          isExpanded: true,
          onChanged: (v) => _emit(_filter.copyWith(sortBy: v ?? _filter.sortBy)),
          items: const [
            DropdownMenuItem(value: SortBy.score, child: Text('Score')),
            DropdownMenuItem(
                value: SortBy.displayOrder, child: Text("Ordre d'affichage")),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _dirButton('Décroissant', _filter.sortDir == SortDir.desc,
                  () => _emit(_filter.copyWith(sortDir: SortDir.desc))),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _dirButton('Croissant', _filter.sortDir == SortDir.asc,
                  () => _emit(_filter.copyWith(sortDir: SortDir.asc))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _brandSection(BuildContext context) {
    final selected = _filter.priorityBrands;
    final query = _search.trim().toLowerCase();
    final filtered = widget.catalog
        .where((b) => query.isEmpty || b.toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Marques prioritaires',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Text('Utiliser toutes les marques',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Switch(
              value: _filter.useAllBrands,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => _emit(_filter.copyWith(
                useAllBrands: v,
                priorityBrands: v ? const [] : _filter.priorityBrands,
              )),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: 'Rechercher des marques...',
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Marques sélectionnées (Ordre de priorité)',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                  onPressed: _clearBrands, child: const Text('Tout effacer')),
            ],
          ),
          for (var i = 0; i < selected.length; i++)
            _selectedRow(i, selected[i]),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Ajouter plus de marques',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final brand in filtered)
              _catalogChip(brand, selected.contains(brand)),
          ],
        ),
      ],
    );
  }

  Widget _selectedRow(int index, String brand) {
    final last = index == _filter.priorityBrands.length - 1;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Text('${index + 1}',
              style: const TextStyle(
                  color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(brand,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: index == 0 ? null : () => _move(index, -1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: last ? null : () => _move(index, 1),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.negative),
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeBrand(brand),
          ),
        ],
      ),
    );
  }

  Widget _catalogChip(String brand, bool selected) {
    return GestureDetector(
      onTap: () => selected ? _removeBrand(brand) : _addBrand(brand),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(brand,
                style: TextStyle(
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(selected ? Icons.remove : Icons.add,
                size: 14,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _dirButton(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primaryLight : null,
        side:
            BorderSide(color: selected ? AppColors.primary : AppColors.divider),
      ),
      child: Text(label,
          style: TextStyle(
              color:
                  selected ? AppColors.primaryDark : AppColors.textSecondary)),
    );
  }
}
