import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/client_profile.dart';
import '../providers/session_flow_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/lumina_ui.dart';
import 'questionnaire_screen.dart';

/// Formulaire de création d'un profil client (étape 1 du parcours).
class NewClientScreen extends ConsumerStatefulWidget {
  final List<CameraDescription> cameras;
  final String? telephoneInitial;

  const NewClientScreen({
    super.key,
    required this.cameras,
    this.telephoneInitial,
  });

  @override
  ConsumerState<NewClientScreen> createState() => _NewClientScreenState();
}

class _NewClientScreenState extends ConsumerState<NewClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _prenomController = TextEditingController();
  final _nomController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _birthDateController = TextEditingController();
  DateTime? _birthDate;
  String? _peauSensible;

  @override
  void initState() {
    super.initState();
    _telephoneController.text = widget.telephoneInitial ?? '';
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 110, now.month, now.day),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Date de naissance du client',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final client = ClientProfile(
      prenom: _prenomController.text.trim(),
      nom: _nomController.text.trim(),
      telephone: _telephoneController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      birthDate: _birthDate,
      peauSensible: _peauSensible ?? 'Je ne sais pas',
    );

    ref.read(sessionFlowProvider.notifier).setClient(client);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuestionnaireScreen(cameras: widget.cameras),
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
            title: 'Nouveau client',
            subtitle: 'Étape 1 · Profil du client',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Form(
                key: _formKey,
                child: LuminaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.badge_outlined,
                                color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Informations du client',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: LuminaUi.navy,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const LuminaFieldLabel('Prénom'),
                      TextFormField(
                        controller: _prenomController,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Prénom du client',
                            icon: Icons.person_outline),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Nom'),
                      TextFormField(
                        controller: _nomController,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Nom du client',
                            icon: Icons.person_outline),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Téléphone'),
                      TextFormField(
                        controller: _telephoneController,
                        keyboardType: TextInputType.phone,
                        decoration: LuminaUi.field(
                            hint: 'Ex. 0612345678',
                            icon: Icons.phone_outlined),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Email (optionnel)'),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: LuminaUi.field(
                            hint: 'email@exemple.com',
                            icon: Icons.mail_outline),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Date de naissance (optionnel)'),
                      TextFormField(
                        controller: _birthDateController,
                        readOnly: true,
                        onTap: _pickBirthDate,
                        decoration: LuminaUi.field(
                            hint: 'jj/mm/aaaa', icon: Icons.cake_outlined),
                      ),
                      const SizedBox(height: 18),
                      const LuminaFieldLabel('Peau sensible ?'),
                      _ChoiceChips(
                        options: const ['Oui', 'Non', 'Je ne sais pas'],
                        value: _peauSensible,
                        onChanged: (v) => setState(() => _peauSensible = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _BottomBar(
            child: LuminaGradientButton(
              label: 'Démarrer le diagnostic',
              icon: Icons.arrow_forward,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur segmenté (chips) pour un choix unique.
class _ChoiceChips extends StatelessWidget {
  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  const _ChoiceChips({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final selected = value == o;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : LuminaUi.fieldFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check_circle,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  o,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : LuminaUi.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Barre d'action fixée en bas, avec ombre douce.
class _BottomBar extends StatelessWidget {
  final Widget child;

  const _BottomBar({required this.child});

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
          child: child,
        ),
      ),
    );
  }
}
