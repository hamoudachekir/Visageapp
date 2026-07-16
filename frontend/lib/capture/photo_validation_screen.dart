import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/lumina_ui.dart';
import 'capture_pose.dart';
import 'pose_capture_screen.dart';

const _green = Color(0xFF22C55E);
const _greenSoft = Color(0xFFE7F8EE);

/// Écran de revue des vues capturées avant l'analyse (look clair Lumina).
/// Permet de reprendre une vue individuellement.
class PhotoValidationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final List<CapturedShot> shots;
  final void Function(List<CapturedShot> shots) onConfirmed;

  const PhotoValidationScreen({
    super.key,
    required this.cameras,
    required this.shots,
    required this.onConfirmed,
  });

  @override
  State<PhotoValidationScreen> createState() => _PhotoValidationScreenState();
}

class _PhotoValidationScreenState extends State<PhotoValidationScreen>
    with SingleTickerProviderStateMixin {
  late List<CapturedShot> _shots;
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _shots = [...widget.shots];
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _retake(CapturePose pose) async {
    final updated = await Navigator.of(context).push<List<CapturedShot>>(
      MaterialPageRoute(
        builder: (_) => PoseCaptureScreen(
          cameras: widget.cameras,
          retakePose: pose,
          existingShots: _shots,
          onCompleted: (shots) => Navigator.of(context).pop(shots),
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _shots = updated);
    }
  }

  /// Animation d'entrée décalée par tuile (fondu + léger glissement/zoom).
  Widget _animate(int index, bool enabled, Widget child) {
    if (!enabled) return child;
    final start = (index * 0.1).clamp(0.0, 0.4);
    final anim = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, (start + 0.7).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 18),
          child: Transform.scale(scale: 0.96 + 0.04 * anim.value, child: c),
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final captured = _shots.length;
    final total = kCaptureFlow.length;
    final complete = captured == total;
    final animate = !MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: Column(
        children: [
          LuminaHeader(
            title: 'Validez vos photos',
            subtitle: "Vérifiez que chaque vue est nette avant l'analyse",
            onBack: () => Navigator.of(context).maybePop(),
          ),
          _CompletionBanner(captured: captured, total: total),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 3 / 4,
              children: [
                for (var i = 0; i < kCaptureFlow.length; i++)
                  _animate(
                    i,
                    animate,
                    _ShotTile(
                      label: kCaptureFlow[i].label,
                      shortLabel: shortPoseLabel(kCaptureFlow[i].pose),
                      icon: kCaptureFlow[i].icon,
                      path: _pathFor(kCaptureFlow[i].pose),
                      onRetake: () => _retake(kCaptureFlow[i].pose),
                    ),
                  ),
              ],
            ),
          ),
          _BottomBar(
            complete: complete,
            remaining: total - captured,
            child: LuminaGradientButton(
              label: "Démarrer l'analyse",
              icon: Icons.arrow_forward,
              onPressed: complete ? () => widget.onConfirmed(_shots) : null,
            ),
          ),
        ],
      ),
    );
  }

  String? _pathFor(CapturePose pose) {
    final matches = _shots.where((s) => s.pose == pose);
    return matches.isEmpty ? null : matches.first.path;
  }
}

/// Bandeau d'état : combien de vues prêtes + message contextuel.
class _CompletionBanner extends StatelessWidget {
  final int captured;
  final int total;

  const _CompletionBanner({required this.captured, required this.total});

  @override
  Widget build(BuildContext context) {
    final complete = captured == total;
    final accent = complete ? _green : AppColors.primary;
    final bg = complete ? _greenSoft : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete ? _green.withAlpha(60) : LuminaUi.hairline,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withAlpha(complete ? 40 : 28),
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.verified_rounded : Icons.photo_camera_outlined,
              color: accent,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete
                      ? 'Les $total vues sont prêtes'
                      : '$captured vue${captured > 1 ? 's' : ''} sur $total',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: LuminaUi.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  complete
                      ? "Vous pouvez lancer l'analyse"
                      : 'Reprenez la ou les vues manquantes',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: LuminaUi.muted,
                  ),
                ),
              ],
            ),
          ),
          _CountDots(captured: captured, total: total, accent: accent),
        ],
      ),
    );
  }
}

class _CountDots extends StatelessWidget {
  final int captured;
  final int total;
  final Color accent;

  const _CountDots({
    required this.captured,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(left: 5),
            width: i < captured ? 9 : 8,
            height: i < captured ? 9 : 8,
            decoration: BoxDecoration(
              color: i < captured ? accent : LuminaUi.hairline,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _ShotTile extends StatelessWidget {
  final String label;
  final String shortLabel;
  final IconData icon;
  final String? path;
  final VoidCallback onRetake;

  const _ShotTile({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.path,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    final hasShot = path != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B1C30),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: hasShot ? _capturedTile() : _emptyTile(),
      ),
    );
  }

  Widget _capturedTile() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(path!), fit: BoxFit.cover),
        // Voile dégradé bas pour la lisibilité du libellé et du bouton.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.transparent, Color(0xB3000000)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Pastille de validation.
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
        ),
        // Libellé (bas gauche) + reprendre (bas droite) sur le voile.
        Positioned(
          left: 12,
          right: 10,
          bottom: 10,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _RetakeButton(label: 'Reprendre', onTap: onRetake),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyTile() {
    return Container(
      color: AppColors.primaryLight,
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: AppColors.primary.withAlpha(90),
          radius: 20,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(150),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 24),
              ),
              const SizedBox(height: 10),
              Text(
                shortLabel,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: LuminaUi.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'À prendre',
                style: GoogleFonts.inter(fontSize: 11, color: LuminaUi.muted),
              ),
              const SizedBox(height: 10),
              _RetakeButton(label: 'Prendre', onTap: onRetake, solid: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petit bouton tactile (effet d'enfoncement) pour reprendre/prendre une vue.
class _RetakeButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool solid;

  const _RetakeButton({
    required this.label,
    required this.onTap,
    this.solid = false,
  });

  @override
  State<_RetakeButton> createState() => _RetakeButtonState();
}

class _RetakeButtonState extends State<_RetakeButton> {
  double _scale = 1;

  void _set(double v) => setState(() => _scale = v);

  @override
  Widget build(BuildContext context) {
    final solid = widget.solid;
    return GestureDetector(
      onTapDown: (_) => _set(0.93),
      onTapUp: (_) {
        _set(1);
        widget.onTap();
      },
      onTapCancel: () => _set(1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: solid ? AppColors.primary : Colors.white.withAlpha(240),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                solid ? Icons.photo_camera : Icons.refresh,
                size: 13,
                color: solid ? Colors.white : AppColors.primary,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: solid ? Colors.white : AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bordure pointillée arrondie (état « vue à prendre »).
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final len = math.min(dash, metric.length - dist);
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _BottomBar extends StatelessWidget {
  final Widget child;
  final bool complete;
  final int remaining;

  const _BottomBar({
    required this.child,
    required this.complete,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LuminaUi.bg,
        border: Border(top: BorderSide(color: LuminaUi.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!complete) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: LuminaUi.muted),
                    const SizedBox(width: 6),
                    Text(
                      'Prenez les $remaining vue${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''} pour continuer',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: LuminaUi.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
