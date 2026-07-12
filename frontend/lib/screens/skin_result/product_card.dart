import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'skin_derivations.dart';

/// Vignette produit recommandé : image, match %, nom, marque, prix, « Ajouter ».
class ProductCard extends StatelessWidget {
  final ProductView view;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const ProductCard({
    super.key,
    required this.view,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final p = view.product;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          boxShadow: const [AppColors.cardShadow],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            productThumb(p.imageUrl, 56),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.positiveLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${view.matchPercent}% Match',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (p.brand != null)
                    Text(p.brand!,
                        style: Theme.of(context).textTheme.bodySmall),
                  if (p.price != null)
                    Text(
                      '${p.price!.toStringAsFixed(3)} TND',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
              ),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniature produit partagée (réseau + repli icône).
Widget productThumb(String? imageUrl, double size) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    child: SizedBox(
      width: size,
      height: size,
      child: imageUrl == null
          ? Container(
              color: AppColors.primaryLight,
              child: const Icon(Icons.spa_outlined, color: AppColors.primary),
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.primaryLight,
                child:
                    const Icon(Icons.spa_outlined, color: AppColors.primary),
              ),
            ),
    ),
  );
}
