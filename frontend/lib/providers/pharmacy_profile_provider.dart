import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pharmacy_profile.dart';
import '../services/pharmacy_api.dart';
import 'auth_provider.dart';

/// Profil pharmacie courant (chargé depuis le backend), avec édition & logo.
class PharmacyProfileNotifier extends AsyncNotifier<PharmacyProfile> {
  PharmacyApi get _api =>
      PharmacyApi(token: ref.read(authProvider).session?.token);

  @override
  Future<PharmacyProfile> build() => _api.getProfile();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_api.getProfile);
  }

  Future<void> updateProfile({
    String? nom,
    String? telephone,
    String? adresse,
    String? ville,
    String? description,
  }) async {
    final updated = await _api.updateProfile(
      nom: nom,
      telephone: telephone,
      adresse: adresse,
      ville: ville,
      description: description,
    );
    state = AsyncData(updated);
    await ref.read(authProvider.notifier).updatePharmacyNom(updated.nom);
  }

  Future<void> uploadLogo(
      Uint8List bytes, String filename, String mime) async {
    final updated = await _api.uploadLogo(bytes, filename, mime);
    state = AsyncData(updated);
  }

  Future<void> deleteLogo() async {
    final updated = await _api.deleteLogo();
    state = AsyncData(updated);
  }
}

final pharmacyProfileProvider =
    AsyncNotifierProvider<PharmacyProfileNotifier, PharmacyProfile>(
  PharmacyProfileNotifier.new,
);
