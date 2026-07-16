import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/client_profile.dart';
import '../models/diagnostic.dart';
import '../models/questionnaire_answers.dart';
import '../services/api_config.dart';

/// Erreur dépôt client porteuse d'un message prêt à afficher.
class ClientRepositoryException implements Exception {
  final String message;
  const ClientRepositoryException(this.message);

  @override
  String toString() => message;
}

abstract class ClientRepository {
  Future<ClientProfile?> findByPhone(String telephone);

  /// Crée le client et renvoie le profil avec son `id` attribué.
  Future<ClientProfile> save(ClientProfile client);

  /// Enregistre les réponses du questionnaire pour un client persisté.
  Future<void> saveDiagnostic(int clientId, QuestionnaireAnswers answers);

  /// Historique des diagnostics d'un client (le plus récent d'abord).
  Future<List<Diagnostic>> diagnosticsFor(int clientId);

  /// Tous les clients de la pharmacie courante (le plus récent d'abord).
  Future<List<ClientProfile>> listClients();
}

/// Dépôt client adossé au backend FastAPI, scopé par pharmacie via le token JWT.
class ApiClientRepository implements ClientRepository {
  final String? token;
  final String baseUrl;

  ApiClientRepository({this.token, this.baseUrl = ApiConfig.baseUrl});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Never _fail(http.Response res) {
    if (res.statusCode == 401) {
      throw const ClientRepositoryException('Session expirée. Reconnectez-vous.');
    }
    throw ClientRepositoryException('Erreur serveur (${res.statusCode}).');
  }

  @override
  Future<ClientProfile?> findByPhone(String telephone) async {
    final uri = Uri.parse('$baseUrl/v1/clients')
        .replace(queryParameters: {'telephone': telephone});
    http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 20),
          );
    } on Exception {
      throw const ClientRepositoryException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    if (list.isEmpty) return null;
    return ClientProfile.fromJson(list.first as Map<String, dynamic>);
  }

  @override
  Future<ClientProfile> save(ClientProfile client) async {
    final uri = Uri.parse('$baseUrl/v1/clients');
    http.Response res;
    try {
      res = await http
          .post(uri, headers: _headers, body: jsonEncode(client.toJson()))
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const ClientRepositoryException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 201 && res.statusCode != 200) _fail(res);
    return ClientProfile.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> saveDiagnostic(int clientId, QuestionnaireAnswers answers) async {
    final uri = Uri.parse('$baseUrl/v1/diagnostics');
    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'client_id': clientId,
              'type_peau': answers.typePeau,
              'tendance_acneique': answers.tendanceAcneique,
              'sensibilite_cutanee': answers.sensibiliteCutanee,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const ClientRepositoryException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 201 && res.statusCode != 200) _fail(res);
  }

  @override
  Future<List<Diagnostic>> diagnosticsFor(int clientId) async {
    final uri = Uri.parse('$baseUrl/v1/clients/$clientId/diagnostics');
    http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 20),
          );
    } on Exception {
      throw const ClientRepositoryException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => Diagnostic.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ClientProfile>> listClients() async {
    final uri = Uri.parse('$baseUrl/v1/clients');
    http.Response res;
    try {
      res = await http.get(uri, headers: _headers).timeout(
            const Duration(seconds: 20),
          );
    } on Exception {
      throw const ClientRepositoryException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => ClientProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Stockage en mémoire (tests / fallback hors-ligne) — perdu à la fermeture.
class InMemoryClientRepository implements ClientRepository {
  final List<ClientProfile> _clients = [];
  int _nextId = 1;

  @override
  Future<ClientProfile?> findByPhone(String telephone) async {
    final matches = _clients.where((c) => c.telephone == telephone);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<ClientProfile> save(ClientProfile client) async {
    final saved = client.copyWith(id: _nextId++);
    _clients.add(saved);
    return saved;
  }

  @override
  Future<void> saveDiagnostic(int clientId, QuestionnaireAnswers answers) async {
    // No-op en mémoire.
  }

  @override
  Future<List<Diagnostic>> diagnosticsFor(int clientId) async => [];

  @override
  Future<List<ClientProfile>> listClients() async =>
      List.unmodifiable(_clients.reversed);
}
