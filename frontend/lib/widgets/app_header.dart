import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Barre supérieure réutilisable : flèche retour (sur les écrans secondaires)
/// à gauche, titre optionnel au centre, nom de la pharmacie + icône caducée
/// à droite (pas d'icône caducée native en Material, on utilise
/// `local_pharmacy` comme équivalent visuel le plus proche).
///
/// Pas de menu/drawer : l'app est un flux unique (accueil → onboarding →
/// capture → résultat), il n'y a pas de destinations secondaires à lister.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String pharmacyName;
  final String? title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const AppHeader({
    super.key,
    this.pharmacyName = 'Pharmacie Kalai - Main Branch',
    this.title,
    this.onBack,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final pharmacyBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          pharmacyName,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.local_pharmacy_outlined,
              color: AppColors.primary, size: 18),
        ),
      ],
    );

    final brandMark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.eco, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        const Text(
          'Lumina',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );

    return AppBar(
      leading: onBack == null
          ? null
          : IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            ),
      automaticallyImplyLeading: false,
      title: title == null
          ? Row(
              children: [
                if (onBack == null) brandMark,
                const Spacer(),
                pharmacyBlock,
              ],
            )
          : Text(
              title!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
      actions: actions,
      shape: const Border(
        bottom: BorderSide(color: AppColors.divider, width: 1),
      ),
    );
  }
}
