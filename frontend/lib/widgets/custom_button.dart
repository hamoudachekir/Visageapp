import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Bouton réutilisable : variante pleine (teal), contour, ou texte/ghost,
/// avec icône optionnelle et état de chargement. Pleine largeur par défaut,
/// cible tactile tablette (56px min, fixée par [AppTheme]).
class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final bool ghost;
  final bool fullWidth;
  final bool loading;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.ghost = false,
    this.fullWidth = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final spinnerColor = outlined || ghost ? AppColors.primary : Colors.white;
    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: spinnerColor,
            ),
          )
        : icon == null
            ? Text(label)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                  Text(label),
                ],
              );

    final effectiveOnPressed = loading ? null : onPressed;

    final button = ghost
        ? TextButton(onPressed: effectiveOnPressed, child: child)
        : outlined
            ? OutlinedButton(onPressed: effectiveOnPressed, child: child)
            : ElevatedButton(onPressed: effectiveOnPressed, child: child);

    if (!fullWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
