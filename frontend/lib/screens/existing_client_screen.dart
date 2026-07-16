import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/session_flow_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/lumina_ui.dart';
import 'client_history_screen.dart';
import 'new_client_screen.dart';

/// Recherche d'un client existant par téléphone, avant sa fiche.
class ExistingClientScreen extends ConsumerStatefulWidget {
  final List<CameraDescription> cameras;

  const ExistingClientScreen({super.key, required this.cameras});

  @override
  ConsumerState<ExistingClientScreen> createState() =>
      _ExistingClientScreenState();
}

class _ExistingClientScreenState extends ConsumerState<ExistingClientScreen> {
  final _telephoneController = TextEditingController();
  bool _searching = false;
  bool _notFound = false;
  String? _error;

  @override
  void dispose() {
    _telephoneController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final telephone = _telephoneController.text.trim();
    if (telephone.isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _notFound = false;
      _error = null;
    });

    try {
      final client =
          await ref.read(clientRepositoryProvider).findByPhone(telephone);
      if (!mounted) return;
      setState(() => _searching = false);

      if (client == null) {
        setState(() => _notFound = true);
        return;
      }

      ref.read(sessionFlowProvider.notifier).setClient(client);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientHistoryScreen(
            client: client,
            cameras: widget.cameras,
          ),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  void _createNewProfile() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NewClientScreen(
          cameras: widget.cameras,
          telephoneInitial: _telephoneController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: Column(
        children: [
          LuminaHeader(
            title: 'Client existant',
            subtitle: 'Retrouvez une fiche par téléphone',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_search_outlined,
                        color: AppColors.primary, size: 38),
                  ),
                  const SizedBox(height: 20),
                  LuminaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LuminaFieldLabel('Numéro de téléphone'),
                        TextField(
                          controller: _telephoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: LuminaUi.field(
                              hint: 'Ex. 0612345678',
                              icon: Icons.phone_outlined),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _Banner(
                            icon: Icons.error_outline,
                            color: AppColors.negative,
                            text: _error!,
                          ),
                        ],
                        const SizedBox(height: 18),
                        LuminaGradientButton(
                          label: _searching ? 'Recherche…' : 'Rechercher',
                          icon: Icons.search,
                          loading: _searching,
                          onPressed: _search,
                        ),
                      ],
                    ),
                  ),
                  if (_notFound) ...[
                    const SizedBox(height: 16),
                    LuminaCard(
                      child: Column(
                        children: [
                          const _Banner(
                            icon: Icons.info_outline,
                            color: AppColors.primary,
                            text: 'Aucun client trouvé avec ce numéro.',
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _createNewProfile,
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
                              label: const Text('Créer un nouveau profil'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side:
                                    const BorderSide(color: Color(0xFFBFE6E8)),
                                minimumSize: const Size(0, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: GoogleFonts.inter(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 13, color: LuminaUi.navy),
            ),
          ),
        ],
      ),
    );
  }
}
