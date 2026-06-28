import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../services/auth_api.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository());

/// État d'authentification courant.
class AuthState {
  final bool loading;
  final AuthSession? session;

  const AuthState({this.loading = false, this.session});

  bool get isLoggedIn => session != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Restaure une session stockée (appelé au démarrage). Renvoie la session.
  Future<AuthSession?> restore() async {
    final session = await _repo.restore();
    state = AuthState(session: session);
    return session;
  }

  /// Tente la connexion. Renvoie null si OK, sinon un message d'erreur.
  Future<String?> login(String email, String password) async {
    state = const AuthState(loading: true);
    try {
      final session = await _repo.login(email, password);
      state = AuthState(session: session);
      return null;
    } on AuthException catch (e) {
      state = const AuthState(loading: false);
      return e.message;
    } catch (_) {
      state = const AuthState(loading: false);
      return 'Une erreur inattendue est survenue.';
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState();
  }

  /// Met à jour le nom de pharmacie en session (badge Home) + stockage.
  Future<void> updatePharmacyNom(String nom) async {
    final s = state.session;
    if (s == null) return;
    await _repo.updatePharmacyNom(nom);
    state = AuthState(
      session: AuthSession(
        token: s.token,
        pharmacyId: s.pharmacyId,
        pharmacyNom: nom,
      ),
    );
  }
}

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
