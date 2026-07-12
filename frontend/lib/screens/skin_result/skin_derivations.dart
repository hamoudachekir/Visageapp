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
int healthScore(SkinCondition c) => (100 - c.score).clamp(0, 100);

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

/// Pourcentage de correspondance produit ⇄ préoccupations signalées.
int matchPercent({
  required ProductRecommendation product,
  required Set<String> flagged,
  required int indexInGroup,
}) {
  final covered = product.matchedConditions.where(flagged.contains).length;
  final coverage = flagged.isEmpty ? 0.0 : covered / flagged.length;
  final rankBonus = (5 - indexInGroup).clamp(0, 5);
  final raw = (70 + 25 * coverage + rankBonus).round();
  return raw.clamp(70, 99);
}

/// Produits recommandés pour une condition (ordre backend préservé).
List<ProductRecommendation> productsForCondition(
        String code, List<ProductRecommendation> recs) =>
    recs.where((r) => r.matchedConditions.contains(code)).toList();

/// Marques présentes dans les recommandations (distinctes, triées).
List<String> brandsInResults(List<ProductRecommendation> recs) {
  final set = <String>{
    for (final r in recs)
      if (r.brand != null && r.brand!.isNotEmpty) r.brand!,
  };
  return set.toList()..sort();
}

enum SortBy { score, displayOrder }

enum SortDir { desc, asc }

class FilterState {
  final SortBy sortBy;
  final SortDir sortDir;
  final bool useAllBrands;
  final List<String> priorityBrands;

  const FilterState({
    this.sortBy = SortBy.score,
    this.sortDir = SortDir.desc,
    this.useAllBrands = true,
    this.priorityBrands = const [],
  });

  FilterState copyWith({
    SortBy? sortBy,
    SortDir? sortDir,
    bool? useAllBrands,
    List<String>? priorityBrands,
  }) =>
      FilterState(
        sortBy: sortBy ?? this.sortBy,
        sortDir: sortDir ?? this.sortDir,
        useAllBrands: useAllBrands ?? this.useAllBrands,
        priorityBrands: priorityBrands ?? this.priorityBrands,
      );
}

class ProductView {
  final ProductRecommendation product;
  final int matchPercent;
  const ProductView({required this.product, required this.matchPercent});
}

/// Vues produit d'une condition : match% (sur ordre backend), puis tri + marques.
List<ProductView> productViewsForCondition({
  required String code,
  required List<ProductRecommendation> recs,
  required Set<String> flagged,
  required FilterState filter,
}) {
  final group = productsForCondition(code, recs);
  final views = <ProductView>[
    for (var i = 0; i < group.length; i++)
      ProductView(
        product: group[i],
        matchPercent:
            matchPercent(product: group[i], flagged: flagged, indexInGroup: i),
      ),
  ];

  // Tri principal (l'ordre initial = « ordre d'affichage »).
  List<ProductView> sorted;
  switch (filter.sortBy) {
    case SortBy.score:
      sorted = [...views]
        ..sort((a, b) => a.matchPercent.compareTo(b.matchPercent));
      break;
    case SortBy.displayOrder:
      sorted = [...views];
      break;
  }
  if (filter.sortDir == SortDir.desc) {
    sorted = sorted.reversed.toList();
  }

  // Priorité marques : tri stable par rang de marque.
  if (!filter.useAllBrands && filter.priorityBrands.isNotEmpty) {
    int rank(ProductView v) {
      final b = v.product.brand;
      final i = b == null ? -1 : filter.priorityBrands.indexOf(b);
      return i < 0 ? filter.priorityBrands.length : i;
    }

    final decorated = [
      for (var i = 0; i < sorted.length; i++) MapEntry(i, sorted[i])
    ]..sort((a, b) {
        final r = rank(a.value).compareTo(rank(b.value));
        return r != 0 ? r : a.key.compareTo(b.key);
      });
    sorted = [for (final e in decorated) e.value];
  }
  return sorted;
}
