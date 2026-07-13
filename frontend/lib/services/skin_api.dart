import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/skin_analysis.dart';
import 'api_config.dart';

/// Erreur d'analyse porteuse d'un message prêt à afficher.
class SkinApiException implements Exception {
  final String message;
  const SkinApiException(this.message);

  @override
  String toString() => message;
}

/// Client HTTP de `POST /v1/skin/analyze` (4 photos, JWT pharmacie).
class SkinApi {
  final String baseUrl;
  final String? token;

  SkinApi({this.baseUrl = ApiConfig.baseUrl, this.token});

  Future<SkinAnalysisResult> analyze({
    required File front,
    required File left,
    required File right,
    required File closeup,
    int? clientId,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/skin/analyze');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    // contentType explicite : le backend rejette application/octet-stream.
    final jpeg = MediaType('image', 'jpeg');
    request.files.add(
        await http.MultipartFile.fromPath('front', front.path, contentType: jpeg));
    request.files.add(
        await http.MultipartFile.fromPath('left', left.path, contentType: jpeg));
    request.files.add(
        await http.MultipartFile.fromPath('right', right.path, contentType: jpeg));
    request.files.add(await http.MultipartFile.fromPath('closeup', closeup.path,
        contentType: jpeg));
    if (clientId != null) {
      request.fields['client_id'] = '$clientId';
    }

    // 4 photos + API externe : délai volontairement long.
    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      String message = 'Erreur serveur (${response.statusCode}).';
      try {
        final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
        if (detail is String && detail.isNotEmpty) message = detail;
      } catch (_) {
        // corps non JSON : on garde le message générique
      }
      throw SkinApiException(message);
    }
    return SkinAnalysisResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Catalogue des marques (`GET /v1/skin/brands`). [] en cas d'erreur.
  Future<List<String>> fetchBrands() async {
    try {
      final uri = Uri.parse('$baseUrl/v1/skin/brands');
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final brands = (body as Map<String, dynamic>)['brands'] as List?;
      return brands?.cast<String>() ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
