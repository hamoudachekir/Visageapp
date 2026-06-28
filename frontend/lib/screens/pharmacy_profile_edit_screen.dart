import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pharmacy_profile.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../services/pharmacy_api.dart';
import '../widgets/lumina_ui.dart';

/// Formulaire d'édition du profil pharmacie (nom, téléphone, adresse, ville,
/// description). L'email reste en lecture seule (identifiant de connexion).
class PharmacyProfileEditScreen extends ConsumerStatefulWidget {
  final PharmacyProfile profile;

  const PharmacyProfileEditScreen({super.key, required this.profile});

  @override
  ConsumerState<PharmacyProfileEditScreen> createState() =>
      _PharmacyProfileEditScreenState();
}

class _PharmacyProfileEditScreenState
    extends ConsumerState<PharmacyProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _telephone;
  late final TextEditingController _adresse;
  late final TextEditingController _ville;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nom = TextEditingController(text: p.nom);
    _telephone = TextEditingController(text: p.telephone ?? '');
    _adresse = TextEditingController(text: p.adresse ?? '');
    _ville = TextEditingController(text: p.ville ?? '');
    _description = TextEditingController(text: p.description ?? '');
  }

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _adresse.dispose();
    _ville.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(pharmacyProfileProvider.notifier).updateProfile(
            nom: _nom.text.trim(),
            telephone: _telephone.text.trim(),
            adresse: _adresse.text.trim(),
            ville: _ville.text.trim(),
            description: _description.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } on PharmacyApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: Column(
        children: [
          LuminaHeader(
            title: 'Modifier le profil',
            subtitle: 'Informations de votre pharmacie',
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
                      const LuminaFieldLabel('Nom de la pharmacie'),
                      TextFormField(
                        controller: _nom,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Ex. Pharmacie du Centre',
                            icon: Icons.local_pharmacy_outlined),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Téléphone'),
                      TextFormField(
                        controller: _telephone,
                        keyboardType: TextInputType.phone,
                        decoration: LuminaUi.field(
                            hint: 'Ex. 71 123 456',
                            icon: Icons.phone_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Adresse'),
                      TextFormField(
                        controller: _adresse,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: LuminaUi.field(
                            hint: 'Rue, numéro',
                            icon: Icons.place_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Ville'),
                      TextFormField(
                        controller: _ville,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Ex. Tunis',
                            icon: Icons.location_city_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Description'),
                      TextFormField(
                        controller: _description,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: LuminaUi.field(
                            hint: 'Votre parapharmacie de confiance',
                            icon: Icons.notes_outlined),
                      ),
                      const SizedBox(height: 24),
                      LuminaGradientButton(
                        label: 'Enregistrer',
                        icon: Icons.check,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
