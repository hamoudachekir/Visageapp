import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/auth_api.dart';

/// Session authentifiée d'une pharmacie.
class AuthSession {
  final String token;
  final int pharmacyId;
  final String pharmacyNom;

  const AuthSession({
    required this.token,
    required this.pharmacyId,
    required this.pharmacyNom,
  });
}

/// Combine l'API d'auth et le stockage sécurisé du token (persistance de
/// session entre deux lancements de l'app).
class AuthRepository {
  final AuthApi _api;
  final FlutterSecureStorage _storage;

  static const _kToken = 'auth_token';
  static const _kPharmId = 'auth_pharmacy_id';
  static const _kPharmNom = 'auth_pharmacy_nom';

  AuthRepository({AuthApi? api, FlutterSecureStorage? storage})
      : _api = api ?? AuthApi(),
        _storage = storage ?? const FlutterSecureStorage();

  Future<AuthSession> login(String email, String password) async {
    final r = await _api.login(email.trim(), password);
    await _storage.write(key: _kToken, value: r.token);
    await _storage.write(key: _kPharmId, value: r.pharmacyId.toString());
    await _storage.write(key: _kPharmNom, value: r.pharmacyNom);
    return AuthSession(
      token: r.token,
      pharmacyId: r.pharmacyId,
      pharmacyNom: r.pharmacyNom,
    );
  }

  Future<void> logout() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kPharmId);
    await _storage.delete(key: _kPharmNom);
  }

  /// Réécrit le nom de pharmacie stocké (après édition du profil).
  Future<void> updatePharmacyNom(String nom) async {
    await _storage.write(key: _kPharmNom, value: nom);
  }

  /// Restaure la session si un token valide est stocké, sinon null.
  Future<AuthSession?> restore() async {
    final token = await _storage.read(key: _kToken);
    if (token == null) return null;
    if (!await _api.validate(token)) {
      await logout();
      return null;
    }
    final id = int.tryParse(await _storage.read(key: _kPharmId) ?? '');
    if (id == null) return null;
    final nom = await _storage.read(key: _kPharmNom) ?? 'Pharmacie';
    return AuthSession(token: token, pharmacyId: id, pharmacyNom: nom);
  }
}
