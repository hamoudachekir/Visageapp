import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Boîte à outils visuelle partagée "Lumina" (look clinique lumineux teal) :
/// en-tête d'écran, libellés, décoration de champ et bouton dégradé.
class LuminaUi {
  LuminaUi._();

  static const navy = Color(0xFF0B1C30);
  static const muted = Color(0xFF5A6B6D);
  static const label = Color(0xFF6E797A);
  static const fieldFill = Color(0xFFEFF5F6);
  static const hairline = Color(0xFFE7EFF0);
  static const bg = Color(0xFFF4F8F9);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12A6AE), Color(0xFF006168)],
  );

  static InputDecoration field({
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: const Color(0xFFAAB7B8), fontSize: 14),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: const Color(0xFF8A9A9C), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: b(Colors.transparent, 1),
      focusedBorder: b(AppColors.primary, 1.6),
      errorBorder: b(AppColors.negative, 1),
      focusedErrorBorder: b(AppColors.negative, 1.6),
    );
  }
}

/// En-tête d'écran : bouton retour rond, titre, sous-titre optionnel, action.
class LuminaHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  const LuminaHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LuminaUi.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              if (onBack != null) ...[
                _CircleIcon(icon: Icons.arrow_back, onTap: onBack!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: LuminaUi.navy,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: LuminaUi.muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: LuminaUi.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: LuminaUi.navy),
        ),
      ),
    );
  }
}

/// Micro-libellé de champ en capitales.
class LuminaFieldLabel extends StatelessWidget {
  final String text;

  const LuminaFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: LuminaUi.label,
        ),
      ),
    );
  }
}

/// Bouton principal : dégradé teal + halo lumineux + état de chargement.
class LuminaGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  const LuminaGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LuminaUi.gradient,
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x4D0C7C84),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 56,
              width: double.infinity,
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (icon != null) ...[
                            const SizedBox(width: 8),
                            Icon(icon, color: Colors.white, size: 20),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte blanche standard (bord doux + ombre légère).
class LuminaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const LuminaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LuminaUi.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B1C30),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}
