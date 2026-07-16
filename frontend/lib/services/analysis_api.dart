import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Résultat de l'analyse renvoyé par le backend `/v1/analyze`.
class AnalysisResult {
  final bool ok;
  final String? raison;
  final int nbVisages;
  final double? confiance;
  final int? ageEstime;
  final String? sexe;

  const AnalysisResult({
    required this.ok,
    this.raison,
    this.nbVisages = 0,
    this.confiance,
    this.ageEstime,
    this.sexe,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final demo = json['demographics'] as Map<String, dynamic>?;
    return AnalysisResult(
      ok: json['ok'] == true,
      raison: json['raison'] as String?,
      nbVisages: (json['nb_visages'] as num?)?.toInt() ?? 0,
      confiance: (json['confiance'] as num?)?.toDouble(),
      ageEstime: (demo?['age_estime'] as num?)?.toInt(),
      sexe: demo?['sexe'] as String?,
    );
  }
}

/// Client HTTP minimal vers le backend FastAPI.
class AnalysisApi {
  /// URL de base du backend.
  ///
  /// ⚠️ Sur un **émulateur Android**, `localhost` pointe vers l'émulateur,
  /// pas vers votre PC : utilisez `http://10.0.2.2:8000`.
  /// Sur un **appareil physique**, mettez l'IP locale de votre PC
  /// (ex. `http://192.168.1.20:8000`).
  final String baseUrl;

  AnalysisApi({this.baseUrl = ApiConfig.baseUrl});

  /// Envoie la photo de face au backend et renvoie l'âge + le sexe.
  Future<AnalysisResult> analyzeFace(File faceImage) async {
    final uri = Uri.parse('$baseUrl/v1/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', faceImage.path));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur backend ${response.statusCode} : ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AnalysisResult.fromJson(body);
  }
}
