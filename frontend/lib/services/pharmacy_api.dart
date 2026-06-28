import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/pharmacy_profile.dart';
import 'api_config.dart';

/// Erreur profil pharmacie porteuse d'un message prêt à afficher.
class PharmacyApiException implements Exception {
  final String message;
  const PharmacyApiException(this.message);

  @override
  String toString() => message;
}

/// Client HTTP du profil pharmacie (scopé par le token JWT).
class PharmacyApi {
  final String? token;
  final String baseUrl;

  PharmacyApi({this.token, this.baseUrl = ApiConfig.baseUrl});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Never _fail(http.Response res) {
    if (res.statusCode == 401) {
      throw const PharmacyApiException('Session expirée. Reconnectez-vous.');
    }
    throw PharmacyApiException('Erreur serveur (${res.statusCode}).');
  }

  PharmacyProfile _parse(http.Response res) => PharmacyProfile.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );

  Future<PharmacyProfile> getProfile() async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('$baseUrl/v1/auth/me'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const PharmacyApiException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    return _parse(res);
  }

  Future<PharmacyProfile> updateProfile({
    String? nom,
    String? telephone,
    String? adresse,
    String? ville,
    String? description,
  }) async {
    final body = <String, dynamic>{
      if (nom != null) 'nom': nom,
      if (telephone != null) 'telephone': telephone,
      if (adresse != null) 'adresse': adresse,
      if (ville != null) 'ville': ville,
      if (description != null) 'description': description,
    };
    http.Response res;
    try {
      res = await http
          .patch(Uri.parse('$baseUrl/v1/pharmacy'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const PharmacyApiException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    return _parse(res);
  }

  Future<PharmacyProfile> uploadLogo(
      Uint8List bytes, String filename, String mime) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/v1/pharmacy/logo'),
    );
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mime),
    ));
    http.Response res;
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on Exception {
      throw const PharmacyApiException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    return _parse(res);
  }

  Future<PharmacyProfile> deleteLogo() async {
    http.Response res;
    try {
      res = await http
          .delete(Uri.parse('$baseUrl/v1/pharmacy/logo'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw const PharmacyApiException(
        'Connexion au serveur impossible. Vérifiez que le backend est lancé.',
      );
    }
    if (res.statusCode != 200) _fail(res);
    return _parse(res);
  }
}
