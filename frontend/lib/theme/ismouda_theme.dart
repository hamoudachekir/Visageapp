import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette et styles partagés de la direction "Ismouda Dark AI".
class IsmoudaColors {
  IsmoudaColors._();

  static const bgTop = Color(0xFF0B0D14);
  static const bgBottom = Color(0xFF0C0E16);
  static const surface = Color(0xFF1E212E);
  static const surfaceGlass = Color(0x8C1E212E); // rgba(30,33,46,.55)

  static const primaryStart = Color(0xFF14B8A6);
  static const primaryEnd = Color(0xFF0C7C84);
  static const accent = Color(0xFF2DD4BF);

  static const green = Color(0xFF1F9D57);
  static const greenBright = Color(0xFF2BC974);
  static const red = Color(0xFFD14B4B);

  static const textPrimary = Color(0xFFECEEF8);
  static const textSecondary = Color(0xFF9DA3BA);
  static const textMuted = Color(0xFF8C92A8);
  static const textFaint = Color(0xFF737A92);

  static const primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryStart, primaryEnd],
  );

  static const logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B6CFF), Color(0xFF6E7BFF)],
  );
}

class IsmoudaText {
  IsmoudaText._();

  static TextStyle get body => GoogleFonts.plusJakartaSans(
        color: IsmoudaColors.textPrimary,
      );

  static TextStyle get heading => GoogleFonts.plusJakartaSans(
        color: IsmoudaColors.textPrimary,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      );

  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        color: IsmoudaColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );
}

/// Fond degradé sombre + halos flous, base de chaque écran Ismouda.
class IsmoudaBackground extends StatelessWidget {
  final Widget child;

  const IsmoudaBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            IsmoudaColors.bgTop,
            Color(0xFF131521),
            IsmoudaColors.bgBottom,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            top: -60,
            left: -40,
            child: _Glow(size: 260, color: Color(0x298C78FF)),
          ),
          const Positioned(
            bottom: 40,
            right: -60,
            child: _Glow(size: 300, color: Color(0x247C83FF)),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final Color color;

  const _Glow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
      ),
    );
  }
}

/// Le losange dégradé arrondi qui sert de logo Ismouda.
class IsmoudaLogo extends StatelessWidget {
  final double size;

  const IsmoudaLogo({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45deg
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: IsmoudaColors.logoGradient,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(size / 2),
            bottomLeft: Radius.circular(size / 2),
          ),
          boxShadow: [
            BoxShadow(
              color: IsmoudaColors.primaryEnd.withAlpha(80),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 2,
            height: size * 0.68,
            color: Colors.white.withAlpha(150),
          ),
        ),
      ),
    );
  }
}

/// En-tête réutilisé sur les écrans internes : logo + wordmark + bloc
/// pharmacie statique (pas de backend d'authentification pour l'instant).
class IsmoudaHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;

  const IsmoudaHeader({super.key, this.onBack});

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    // Note : on s'appuie sur le vrai widget AppBar (plutôt qu'un Container
    // dessiné à la main) pour que l'encart sous la barre de statut système
    // soit géré automatiquement — un Container nu ignore cet espace et se
    // fait recouvrir par l'horloge/la batterie en haut de l'écran.
    return AppBar(
      backgroundColor: const Color(0xBD161924),
      elevation: 0,
      leadingWidth: onBack != null ? 56 : 16,
      leading: onBack != null
          ? IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: IsmoudaColors.textMuted),
            )
          : const SizedBox.shrink(),
      titleSpacing: 0,
      title: Row(
        children: [
          const IsmoudaLogo(size: 30),
          const SizedBox(width: 9),
          Text(
            'Lumina',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0C7C84),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Pharmacie Kalai',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: IsmoudaColors.textPrimary,
                ),
              ),
              Text(
                'Main Branch',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  color: IsmoudaColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
      shape: const Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
    );
  }
}

/// Bouton pleine largeur au dégradé primaire, utilisé pour les CTA principaux.
class PrimaryGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const PrimaryGradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              gradient: IsmoudaColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: IsmoudaColors.primaryEnd.withAlpha(80),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 10),
                  Icon(icon, color: Colors.white, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
