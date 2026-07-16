import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';

/// Écran de démarrage : panneau teal plein cadre, révélation animée du
/// logo puis du nom de l'app. Redirige automatiquement vers l'accueil
/// après 2.2 secondes.
class SplashScreen extends ConsumerStatefulWidget {
  final void Function(bool isLoggedIn) onResolved;

  const SplashScreen({super.key, required this.onResolved});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textOffset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _textOffset = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
    _boot();
  }

  /// Restaure une éventuelle session pendant l'animation, puis route vers
  /// l'accueil (connecté) ou l'écran de connexion.
  Future<void> _boot() async {
    final restoreFuture = ref.read(authProvider.notifier).restore();
    await Future.delayed(const Duration(milliseconds: 2200));
    final session = await restoreFuture;
    if (!mounted) return;
    widget.onResolved(session != null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoOpacity,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.eco, color: AppColors.primary, size: 48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _textOpacity,
                  child: SlideTransition(
                    position: _textOffset,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lumina',
                          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                color: Colors.white,
                                fontSize: 34,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "L'assistant d'analyse de peau",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withAlpha(214),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
