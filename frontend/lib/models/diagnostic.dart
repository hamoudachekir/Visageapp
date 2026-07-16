/// Un diagnostic enregistré (une visite) : réponses au questionnaire et,
/// si l'analyse photo a eu lieu, l'âge estimé et le sexe.
class Diagnostic {
  final int id;
  final String typePeau;
  final String tendanceAcneique;
  final String sensibiliteCutanee;
  final int? ageEstime;
  final String? sexe;
  final DateTime? createdAt;

  const Diagnostic({
    required this.id,
    required this.typePeau,
    required this.tendanceAcneique,
    required this.sensibiliteCutanee,
    this.ageEstime,
    this.sexe,
    this.createdAt,
  });

  factory Diagnostic.fromJson(Map<String, dynamic> json) => Diagnostic(
        id: (json['id'] as num).toInt(),
        typePeau: json['type_peau'] as String,
        tendanceAcneique: json['tendance_acneique'] as String,
        sensibiliteCutanee: json['sensibilite_cutanee'] as String,
        ageEstime: (json['age_estime'] as num?)?.toInt(),
        sexe: json['sexe'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );
}
