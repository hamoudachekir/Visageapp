import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/client_profile.dart';
import '../models/pharmacy_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../providers/session_flow_provider.dart';
import '../services/api_config.dart';
import '../services/pharmacy_api.dart';
import '../theme/app_colors.dart';
import '../widgets/lumina_ui.dart';
import 'client_history_screen.dart';
import 'existing_client_screen.dart';
import 'new_client_screen.dart';
import 'pharmacy_profile_edit_screen.dart';
import 'session_type_dialog.dart';

const double _heroHeight = 300;
const double _sheetOverlap = 34;

/// Coquille principale : 3 onglets (Analyse, Historique, Profil) + barre de
/// navigation basse.
class HomeScreen extends ConsumerStatefulWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({super.key, required this.cameras});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  Future<void> _chooseSessionType() async {
    ref.read(sessionFlowProvider.notifier).reset();
    final type = await showSessionTypeDialog(context);
    if (type == null || !mounted) return;

    final screen = type == SessionType.nouveauClient
        ? NewClientScreen(cameras: widget.cameras)
        : ExistingClientScreen(cameras: widget.cameras);

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final pharmacyName =
        ref.watch(authProvider).session?.pharmacyNom ?? 'Pharmacie';

    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: IndexedStack(
        index: _index,
        children: [
          _AnalyseTab(
            pharmacyName: pharmacyName,
            onStart: _chooseSessionType,
            onLogout: _logout,
          ),
          _HistoriqueTab(cameras: widget.cameras),
          _ProfilTab(onLogout: _logout),
        ],
      ),
      bottomNavigationBar: _LuminaBottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

// ───────────────────────── Onglet Analyse ─────────────────────────

class _AnalyseTab extends StatelessWidget {
  final String pharmacyName;
  final VoidCallback onStart;
  final VoidCallback onLogout;

  const _AnalyseTab({
    required this.pharmacyName,
    required this.onStart,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _heroHeight,
            child: _HeroPanel(pharmacyName: pharmacyName, onLogout: onLogout),
          ),
          Positioned(
            top: _heroHeight - _sheetOverlap,
            left: 0,
            right: 0,
            bottom: 0,
            child: _ContentSheet(onStart: onStart),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String pharmacyName;
  final VoidCallback onLogout;

  const _HeroPanel({required this.pharmacyName, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _heroHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13A7AF), Color(0xFF00555B)],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, -0.2),
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _PharmacyBadge(
                        pharmacyName: pharmacyName, onLogout: onLogout),
                  ),
                  const Spacer(),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33001F22),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child:
                        const Icon(Icons.eco, color: Color(0xFF0C7C84), size: 38),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Lumina',
                    style: GoogleFonts.fraunces(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "L'assistant d'analyse de peau",
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withAlpha(214),
                    ),
                  ),
                  const SizedBox(height: 20 + _sheetOverlap),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PharmacyBadge extends StatelessWidget {
  final String pharmacyName;
  final VoidCallback onLogout;

  const _PharmacyBadge({required this.pharmacyName, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Compte',
      onSelected: (v) {
        if (v == 'logout') onLogout();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 10),
              Text('Se déconnecter'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(40),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withAlpha(46)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_pharmacy_outlined,
                color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              pharmacyName,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ContentSheet extends StatelessWidget {
  final VoidCallback onStart;

  const _ContentSheet({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LuminaUi.bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Aidez vos clients à découvrir\nles besoins de leur peau.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 25,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: const Color(0xFF0B1C30),
                  ),
                ),
                const SizedBox(height: 24),
                _StartButton(onTap: onStart),
                const SizedBox(height: 24),
                const _FlowSteps(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final VoidCallback onTap;

  const _StartButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LuminaUi.gradient,
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D0C7C84),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(46),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Démarrer une nouvelle analyse',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Analyse guidée · résultat en ~60 s',
                        style: GoogleFonts.inter(
                          color: Colors.white.withAlpha(210),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowSteps extends StatelessWidget {
  const _FlowSteps();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Step(n: '1', label: 'Profil'),
        _StepLink(),
        _Step(n: '2', label: 'Questionnaire'),
        _StepLink(),
        _Step(n: '3', label: 'Photos'),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String label;

  const _Step({required this.n, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCFE9EB)),
          ),
          child: Text(
            n,
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: const Color(0xFF5A6B6D),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StepLink extends StatelessWidget {
  const _StepLink();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 1.5,
      margin: const EdgeInsets.only(bottom: 20),
      color: const Color(0xFFCFE0E1),
    );
  }
}

// ───────────────────────── Onglet Historique ─────────────────────────

class _HistoriqueTab extends ConsumerStatefulWidget {
  final List<CameraDescription> cameras;

  const _HistoriqueTab({required this.cameras});

  @override
  ConsumerState<_HistoriqueTab> createState() => _HistoriqueTabState();
}

class _HistoriqueTabState extends ConsumerState<_HistoriqueTab> {
  late Future<List<ClientProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(clientRepositoryProvider).listClients();
  }

  void _reload() {
    setState(() {
      _future = ref.read(clientRepositoryProvider).listClients();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Column(
        children: [
          LuminaHeader(
            title: 'Historique',
            subtitle: 'Vos clients enregistrés',
            trailing: _CircleAction(icon: Icons.refresh, onTap: _reload),
          ),
          Expanded(
            child: FutureBuilder<List<ClientProfile>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _EmptyState(
                    icon: Icons.error_outline,
                    text: snap.error.toString(),
                  );
                }
                final clients = snap.data ?? const [];
                if (clients.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.people_outline,
                    text: 'Aucun client enregistré pour le moment.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: clients.length,
                  itemBuilder: (context, i) => _ClientRow(
                    client: clients[i],
                    onTap: () {
                      ref
                          .read(sessionFlowProvider.notifier)
                          .setClient(clients[i]);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ClientHistoryScreen(
                          client: clients[i],
                          cameras: widget.cameras,
                        ),
                      ));
                    },
                  ),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  final ClientProfile client;
  final VoidCallback onTap;

  const _ClientRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initials = (client.prenom.isNotEmpty ? client.prenom[0] : '') +
        (client.nom.isNotEmpty ? client.nom[0] : '');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: LuminaUi.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.nomComplet,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: LuminaUi.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      client.telephone,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, color: LuminaUi.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9AAAAB)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Onglet Profil ─────────────────────────

class _ProfilTab extends ConsumerWidget {
  final VoidCallback onLogout;

  const _ProfilTab({required this.onLogout});

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime =
        picked.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    try {
      await ref
          .read(pharmacyProfileProvider.notifier)
          .uploadLogo(bytes, picked.name, mime);
    } on PharmacyApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pharmacyProfileProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Column(
        children: [
          const LuminaHeader(title: 'Profil', subtitle: 'Votre pharmacie'),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ProfilError(
                message: e.toString(),
                onRetry: () =>
                    ref.read(pharmacyProfileProvider.notifier).refresh(),
              ),
              data: (profile) => _ProfilContent(
                profile: profile,
                token: ref.watch(authProvider).session?.token,
                onEditProfile: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PharmacyProfileEditScreen(profile: profile),
                  ),
                ),
                onEditLogo: () => _pickAndUpload(context, ref),
                onLogout: onLogout,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilContent extends StatelessWidget {
  final PharmacyProfile profile;
  final String? token;
  final VoidCallback onEditProfile;
  final VoidCallback onEditLogo;
  final VoidCallback onLogout;

  const _ProfilContent({
    required this.profile,
    required this.token,
    required this.onEditProfile,
    required this.onEditLogo,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          LuminaCard(
            child: Column(
              children: [
                _LogoAvatar(
                  profile: profile,
                  token: token,
                  onTap: onEditLogo,
                ),
                const SizedBox(height: 14),
                Text(
                  profile.nom,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LuminaUi.navy,
                  ),
                ),
                if (profile.description != null &&
                    profile.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.description!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: LuminaUi.muted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  profile.email,
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: LuminaUi.label),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LuminaCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Téléphone',
                  value: profile.telephone,
                ),
                const Divider(height: 1, color: LuminaUi.hairline),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Adresse',
                  value: profile.adresse,
                ),
                const Divider(height: 1, color: LuminaUi.hairline),
                _InfoRow(
                  icon: Icons.location_city_outlined,
                  label: 'Ville',
                  value: profile.ville,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: LuminaGradientButton(
              label: 'Modifier le profil',
              icon: Icons.edit_outlined,
              onPressed: onEditProfile,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Se déconnecter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.negative,
                side: const BorderSide(color: Color(0xFFE7CFCF)),
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.inter(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoAvatar extends StatelessWidget {
  final PharmacyProfile profile;
  final String? token;
  final VoidCallback onTap;

  const _LogoAvatar({
    required this.profile,
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = profile.nom.trim().isEmpty
        ? 'P'
        : profile.nom.trim()[0].toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              gradient: LuminaUi.gradient,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: profile.hasLogo && token != null
                ? Image.network(
                    '${ApiConfig.baseUrl}/v1/pharmacy/logo?v=${profile.logoCacheKey}',
                    headers: {'Authorization': 'Bearer $token'},
                    fit: BoxFit.cover,
                    width: 84,
                    height: 84,
                    errorBuilder: (_, __, ___) => Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Text(
                    initials,
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: LuminaUi.hairline),
              ),
              child: const Icon(Icons.photo_camera,
                  size: 15, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 13.5, color: LuminaUi.muted),
          ),
          const Spacer(),
          Text(
            filled ? value! : 'Ajouter',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: filled ? LuminaUi.navy : LuminaUi.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfilError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 44, color: AppColors.negative),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13.5, color: LuminaUi.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Barre de navigation ─────────────────────────

class _LuminaBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _LuminaBottomNav({required this.index, required this.onTap});

  static const _items = [
    (icon: Icons.camera_alt_outlined, active: Icons.camera_alt, label: 'Analyse'),
    (icon: Icons.history_outlined, active: Icons.history, label: 'Historique'),
    (icon: Icons.person_outline, active: Icons.person, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: LuminaUi.hairline)),
        boxShadow: [
          BoxShadow(color: Color(0x0F0B1C30), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    item: _items[i],
                    selected: i == index,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ({IconData icon, IconData active, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : const Color(0xFF94A3A4);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.active : item.icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleAction({required this.icon, required this.onTap});

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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFFAAB7B8)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: LuminaUi.muted),
            ),
          ],
        ),
      ),
    );
  }
}
