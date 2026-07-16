import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

const _heroHeight = 340.0;
const _cardOverlap = 36.0;

/// Écran de connexion pharmacie — panneau teal immersif (marque) surmonté
/// d'une carte blanche qui le chevauche. Logo lumineux + mot-symbole sérif.
class LoginScreen extends ConsumerStatefulWidget {
  final VoidCallback onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Renseignez votre email et votre mot de passe.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await ref.read(authProvider.notifier).login(email, password);
    if (!mounted) return;
    if (error == null) {
      widget.onLoggedIn();
    } else {
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _comingSoon(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F8F9),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 92 + bottomInset),
              child: Column(
                children: [
                  const _Hero(),
                  Transform.translate(
                    offset: const Offset(0, -_cardOverlap),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _FadeInUp(
                          child: Column(
                            children: [
                              _LoginCard(
                                emailController: _emailController,
                                passwordController: _passwordController,
                                passwordVisible: _passwordVisible,
                                loading: _loading,
                                error: _error,
                                onTogglePassword: () => setState(() =>
                                    _passwordVisible = !_passwordVisible),
                                onForgotPassword: () => _comingSoon(
                                    'Contactez votre administrateur pour '
                                    'réinitialiser votre mot de passe.'),
                                onSubmit: _submit,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _RequestAccess(
                                onPressed: () => _comingSoon(
                                    'Pour demander un accès, contactez '
                                    'contact@lumina.com.'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _StatusBar(),
          ],
        ),
      ),
    );
  }
}

/// Panneau teal immersif avec halo lumineux, logo et marque.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _heroHeight,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13A7AF), Color(0xFF00555B)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Stack(
        children: [
          // Halo lumineux (signature "Lumina").
          Align(
            alignment: const Alignment(0, -0.35),
            child: Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33001F22),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.eco, color: Color(0xFF0C7C84), size: 44),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Lumina',
                    style: GoogleFonts.fraunces(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      height: 1.0,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "ASSISTANT D'ANALYSE DE PEAU",
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.2,
                      color: Colors.white.withAlpha(210),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte de connexion blanche, chevauchant le panneau teal.
class _LoginCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool passwordVisible;
  final bool loading;
  final String? error;
  final VoidCallback onTogglePassword;
  final VoidCallback onForgotPassword;
  final VoidCallback onSubmit;

  const _LoginCard({
    required this.emailController,
    required this.passwordController,
    required this.passwordVisible,
    required this.loading,
    required this.error,
    required this.onTogglePassword,
    required this.onForgotPassword,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE7EFF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B1C30),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accès pharmacie',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0B1C30),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Connectez-vous à votre espace de diagnostic.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.4,
                color: const Color(0xFF5A6B6D),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _FieldLabel('Identifiant'),
            const SizedBox(height: 7),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                hint: 'pharmacien@exemple.com',
                icon: Icons.mail_outline,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _FieldLabel('Mot de passe'),
            const SizedBox(height: 7),
            TextField(
              controller: passwordController,
              obscureText: !passwordVisible,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
              decoration: _fieldDecoration(
                hint: '••••••••',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF8A9A9C),
                    size: 20,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onForgotPassword,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  foregroundColor: AppColors.primary,
                  textStyle: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppColors.negative),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        error!,
                        style: GoogleFonts.inter(
                          color: AppColors.negative,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            _GradientButton(loading: loading, onPressed: onSubmit),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: const Color(0xFFAAB7B8), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF8A9A9C), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFEFF5F6),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 17),
      enabledBorder: border(Colors.transparent, 1),
      focusedBorder: border(AppColors.primary, 1.6),
    );
  }
}

/// Bouton principal dégradé teal avec halo lumineux + état de chargement.
class _GradientButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;

  const _GradientButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF12A6AE), Color(0xFF006168)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D0C7C84),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onPressed,
          child: SizedBox(
            height: 56,
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
                          'Se connecter',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward,
                            color: Colors.white, size: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: const Color(0xFF6E797A),
        ),
      ),
    );
  }
}

/// Bloc bas : « Pas encore d'accès ? » + pilule « Demander un accès ».
class _RequestAccess extends StatelessWidget {
  final VoidCallback onPressed;

  const _RequestAccess({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "Vous n'avez pas encore d'accès ?",
          style: GoogleFonts.inter(
              fontSize: 13.5, color: const Color(0xFF5A6B6D)),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add_business_outlined, size: 18),
          label: const Text('Demander un accès'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFCFE0E1)),
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: 10),
            shape: const StadiumBorder(),
            textStyle:
                GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Barre d'état contextuelle fixée en bas.
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            AppSpacing.lg, 10, AppSpacing.lg, 10 + bottomInset),
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          border: Border(top: BorderSide(color: Color(0xFFE4EDEE))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('Connectée • En ligne', style: _statusStyle),
              ],
            ),
            Row(
              children: [
                Text('85%', style: _statusStyle),
                const SizedBox(width: 4),
                const Icon(Icons.battery_charging_full,
                    size: 16, color: Color(0xFF6E797A)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final _statusStyle = GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: const Color(0xFF6E797A),
  );
}

/// Entrée douce : fondu + léger glissement vers le haut au chargement.
class _FadeInUp extends StatelessWidget {
  final Widget child;

  const _FadeInUp({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
