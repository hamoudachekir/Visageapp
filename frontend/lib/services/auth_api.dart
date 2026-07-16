import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Erreur d'authentification porteuse d'un message prêt à afficher.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Réponse de `/v1/auth/login`.
class AuthResult {
  final String token;
  final int pharmacyId;
  final String pharmacyNom;
  final String pharmacyEmail;

  const AuthResult({
    required this.token,
    required this.pharmacyId,
    required this.pharmacyNom,
    required this.pharmacyEmail,
  });
}

/// Client HTTP des endpoints d'authentification.
class AuthApi {
  final String baseUrl;

  AuthApi({this.baseUrl = ApiConfig.baseUrl});

  Future<AuthResult> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/v1/auth/login');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const AuthException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final ph = body['pharmacy'] as Map<String, dynamic>;
      return AuthResult(
        token: body['token'] as String,
        pharmacyId: (ph['id'] as num).toInt(),
        pharmacyNom: ph['nom'] as String,
        pharmacyEmail: ph['email'] as String,
      );
    }
    if (response.statusCode == 401) {
      throw const AuthException('Email ou mot de passe incorrect');
    }
    throw AuthException('Erreur serveur (${response.statusCode}).');
  }

  /// Vérifie qu'un token est encore accepté par le backend (GET /v1/auth/me).
  Future<bool> validate(String token) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/v1/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } on Exception {
      return false;
    }
  }
}
