// Dérivations pures du diagnostic — testables sans widget.
// Le `score` backend d'une condition = sévérité (plus haut = pire).
import '../../models/skin_analysis.dart';

enum Severity { faible, moderee, marquee }

Severity severityBand(int rawScore) {
  if (rawScore < 30) return Severity.faible;
  if (rawScore < 60) return Severity.moderee;
  return Severity.marquee;
}

String severityLabel(Severity s) {
  switch (s) {
    case Severity.faible:
      return 'faible';
    case Severity.moderee:
      return 'modérée';
    case Severity.marquee:
      return 'marquée';
  }
}

/// Score « santé » 0-100 affiché (plus haut = plus sain).
int healthScore(SkinCondition c) => 100 - c.score;

/// Moyenne arrondie des scores santé ; null si aucune condition.
int? globalScore(List<SkinCondition> conditions) {
  if (conditions.isEmpty) return null;
  final sum = conditions.fold<int>(0, (a, c) => a + healthScore(c));
  return (sum / conditions.length).round();
}

String globalLabel(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 65) return 'Bon';
  if (score >= 50) return 'Correct';
  return 'À améliorer';
}

/// Codes des conditions signalées (au-dessus du seuil de recommandation).
Set<String> flaggedCodes(List<SkinCondition> conditions) =>
    {for (final c in conditions) if (c.score >= 30) c.code};

/// Conditions prioritaires (score >= 30), triées du plus sévère au moins.
List<SkinCondition> priorityConditions(List<SkinCondition> conditions) {
  final list = conditions.where((c) => c.score >= 30).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return list;
}

/// Toutes les conditions, triées par score santé décroissant.
List<SkinCondition> reportConditions(List<SkinCondition> conditions) {
  final list = [...conditions]
    ..sort((a, b) => healthScore(b).compareTo(healthScore(a)));
  return list;
}

class Observation {
  final List<String> forts;
  final List<String> vigilance;
  const Observation({required this.forts, required this.vigilance});
}

/// Points forts = jusqu'à 4 conditions saines (score < 30) ; à surveiller = le reste.
Observation deriveObservation(List<SkinCondition> conditions) {
  final forts = (conditions.where((c) => c.score < 30).toList()
        ..sort((a, b) => healthScore(b).compareTo(healthScore(a))))
      .take(4)
      .map((c) => c.labelFr)
      .toList();
  final vigilance = (conditions.where((c) => c.score >= 30).toList()
        ..sort((a, b) => b.score.compareTo(a.score)))
      .map((c) => c.labelFr)
      .toList();
  return Observation(forts: forts, vigilance: vigilance);
}
