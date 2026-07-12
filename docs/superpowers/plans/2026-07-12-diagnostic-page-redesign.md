# Diagnostic Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `SkinResultScreen` in a "Clinique premium" style whose every value is derived on-device from the real `SkinAnalysisResult`, with per-condition product reveal, a product detail sheet, filter/sort, and a detailed report.

**Architecture:** Pure, unit-tested derivation functions + view-models in `skin_derivations.dart`; focused presentational sub-widgets under `lib/screens/skin_result/`; a small stateful `SkinResultScreen` shell owning UI state (filter/sort, expanded conditions, report toggle) and wiring stub callbacks. The captured front photo is threaded through `capture_flow.dart` for the hero. No backend/DB/schema changes.

**Tech Stack:** Flutter (Dart, package `analyse_faciale`), `flutter_test`. Existing theme tokens `AppColors` / `AppSpacing`. No new dependencies.

## Global Constraints

- Flutter only. No backend, DB, schema, or dependency changes.
- Package import root is `package:analyse_faciale/...`.
- Every on-screen value is derived from the real `SkinAnalysisResult`; nothing is faked. Deferred features are hidden; stubbed buttons fire no-op callbacks (SnackBar).
- All UI copy is French.
- `healthScore = 100 - condition.score` (backend `score` = severity, higher = worse).
- Severity bands from RAW score: `< 30` faible · `30–59` modérée · `≥ 60` marquée.
- Global bands: `≥ 80` Excellent · `65–79` Bon · `50–64` Correct · `< 50` À améliorer.
- Priority conditions = raw `score ≥ 30`, sorted worst-first.
- Match %: `clamp(round(70 + 25*coverage + rankBonus), 70, 99)`, `coverage = covered/max(1,|flagged|)`, `rankBonus = clamp(5 - indexInGroup, 0, 5)`.
- Price format: `price.toStringAsFixed(3)` + `' TND'`.
- `SkinResultScreen.frontPhoto` is an **optional** `File?` (default null) so existing callers stay valid.
- Style: `AppColors.primary 0xFF0C7C84`, `background 0xFFF8F9FF`, `AppColors.cardShadow`, `AppSpacing.radiusLg`, 8-pt spacing.
- TDD, frequent commits. Run `flutter test` and `flutter analyze` (must stay clean).

---

## File Structure

- Create `frontend/lib/screens/skin_result/skin_derivations.dart` — pure logic + view-models (`Severity`, `Observation`, `SortBy`, `SortDir`, `FilterState`, `ProductView`).
- Create `frontend/lib/screens/skin_result/severity_style.dart` — Severity → Color mapping (widget layer).
- Create `frontend/lib/screens/skin_result/diagnostic_hero.dart` — `DiagnosticHero`.
- Create `frontend/lib/screens/skin_result/product_card.dart` — `ProductCard`.
- Create `frontend/lib/screens/skin_result/product_detail_sheet.dart` — `ProductDetailSheet`.
- Create `frontend/lib/screens/skin_result/condition_card.dart` — `ConditionCard`.
- Create `frontend/lib/screens/skin_result/product_filter_bar.dart` — `ProductFilterBar`.
- Create `frontend/lib/screens/skin_result/observation_card.dart` — `ObservationCard`.
- Create `frontend/lib/screens/skin_result/detailed_report.dart` — `DetailedReport`.
- Create `frontend/lib/screens/skin_result/routine_placeholder.dart` — `RoutinePlaceholder`.
- Modify `frontend/lib/screens/skin_result_screen.dart` — rewrite as stateful shell.
- Modify `frontend/lib/capture/capture_flow.dart` — pass `frontPhoto: front`.
- Create tests under `frontend/test/skin_result/`.

All `flutter` commands run from `frontend/`.

---

### Task 1: Score / severity / global / observation / report derivations

**Files:**
- Create: `frontend/lib/screens/skin_result/skin_derivations.dart`
- Test: `frontend/test/skin_result/skin_derivations_scores_test.dart`

**Interfaces:**
- Consumes: `SkinCondition` from `package:analyse_faciale/models/skin_analysis.dart` (`{code, labelFr, score, severity, zones}`).
- Produces: `enum Severity { faible, moderee, marquee }`; `Severity severityBand(int)`; `String severityLabel(Severity)`; `int healthScore(SkinCondition)`; `int? globalScore(List<SkinCondition>)`; `String globalLabel(int)`; `Set<String> flaggedCodes(List<SkinCondition>)`; `List<SkinCondition> priorityConditions(List<SkinCondition>)`; `List<SkinCondition> reportConditions(List<SkinCondition>)`; `class Observation { List<String> forts; List<String> vigilance; }`; `Observation deriveObservation(List<SkinCondition>)`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/skin_derivations_scores_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter_test/flutter_test.dart';

SkinCondition cond(String code, int score, {String? label}) => SkinCondition(
      code: code,
      labelFr: label ?? code,
      score: score,
      severity: 'x',
    );

void main() {
  test('healthScore inverts raw score', () {
    expect(healthScore(cond('redness', 28)), 72);
    expect(healthScore(cond('acne', 0)), 100);
  });

  test('severityBand thresholds', () {
    expect(severityBand(29), Severity.faible);
    expect(severityBand(30), Severity.moderee);
    expect(severityBand(59), Severity.moderee);
    expect(severityBand(60), Severity.marquee);
  });

  test('severityLabel is French', () {
    expect(severityLabel(Severity.faible), 'faible');
    expect(severityLabel(Severity.moderee), 'modérée');
    expect(severityLabel(Severity.marquee), 'marquée');
  });

  test('globalScore is mean of health, rounded; null when empty', () {
    expect(globalScore([]), isNull);
    // health 80 + 60 => mean 70
    expect(globalScore([cond('a', 20), cond('b', 40)]), 70);
  });

  test('globalLabel bands', () {
    expect(globalLabel(80), 'Excellent');
    expect(globalLabel(79), 'Bon');
    expect(globalLabel(65), 'Bon');
    expect(globalLabel(64), 'Correct');
    expect(globalLabel(50), 'Correct');
    expect(globalLabel(49), 'À améliorer');
  });

  test('flaggedCodes are score >= 30', () {
    expect(flaggedCodes([cond('a', 30), cond('b', 10), cond('c', 55)]),
        {'a', 'c'});
  });

  test('priorityConditions filters >=30 and sorts worst-first', () {
    final out = priorityConditions([cond('a', 30), cond('b', 70), cond('c', 5)]);
    expect(out.map((c) => c.code).toList(), ['b', 'a']);
  });

  test('reportConditions sorts by health descending (raw ascending)', () {
    final out = reportConditions([cond('a', 40), cond('b', 10), cond('c', 90)]);
    expect(out.map((c) => c.code).toList(), ['b', 'a', 'c']);
  });

  test('deriveObservation splits forts (<30, top4 healthiest) and vigilance', () {
    final obs = deriveObservation([
      cond('r', 40, label: 'Rougeurs'),
      cond('s', 35, label: 'Sébum'),
      cond('w', 5, label: 'Rides'),
      cond('t', 8, label: 'Taches'),
    ]);
    expect(obs.forts, ['Rides', 'Taches']);
    expect(obs.vigilance, ['Rougeurs', 'Sébum']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/skin_derivations_scores_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'skin_derivations.dart'` / undefined names.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/skin_derivations.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/skin_derivations_scores_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/skin_derivations.dart frontend/test/skin_result/skin_derivations_scores_test.dart
git commit -m "feat(diag): dérivations scores/sévérité/global/observation"
```

---

### Task 2: Product grouping / match% / filter+sort derivations

**Files:**
- Modify: `frontend/lib/screens/skin_result/skin_derivations.dart` (append)
- Test: `frontend/test/skin_result/skin_derivations_products_test.dart`

**Interfaces:**
- Consumes: `ProductRecommendation` (`{productId, name, brand?, price?, imageUrl?, reasonFr, matchedConditions}`); `flaggedCodes` from Task 1.
- Produces: `int matchPercent({required ProductRecommendation product, required Set<String> flagged, required int indexInGroup})`; `List<ProductRecommendation> productsForCondition(String code, List<ProductRecommendation> recs)`; `List<String> brandsInResults(List<ProductRecommendation> recs)`; `enum SortBy { score, displayOrder }`; `enum SortDir { desc, asc }`; `class FilterState { SortBy sortBy; SortDir sortDir; bool useAllBrands; List<String> priorityBrands; FilterState copyWith({...}); }` (const default `SortBy.score`, `SortDir.desc`, `useAllBrands=true`, `priorityBrands=[]`); `class ProductView { ProductRecommendation product; int matchPercent; }`; `List<ProductView> productViewsForCondition({required String code, required List<ProductRecommendation> recs, required Set<String> flagged, required FilterState filter})`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/skin_derivations_products_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter_test/flutter_test.dart';

ProductRecommendation prod(
  int id, {
  String? brand,
  List<String> matched = const [],
}) =>
    ProductRecommendation(
      productId: id,
      name: 'P$id',
      brand: brand,
      reasonFr: 'r',
      matchedConditions: matched,
    );

void main() {
  const flagged = {'redness', 'oiliness', 'dark_circles'};

  test('matchPercent: coverage + rank bonus, clamped', () {
    // covers 1/3 => 70 + 8.33 + rankBonus
    expect(
        matchPercent(
            product: prod(1, matched: ['redness']),
            flagged: flagged,
            indexInGroup: 0),
        83); // 70 + 8 (round of 8.33) ... exact below
    // covers 2/3 => 70 + 16.67 + 5 => 92
    expect(
        matchPercent(
            product: prod(2, matched: ['redness', 'oiliness']),
            flagged: flagged,
            indexInGroup: 0),
        92);
    // rank bonus decays; index 6 => bonus 0
    expect(
        matchPercent(
            product: prod(3, matched: ['redness']),
            flagged: flagged,
            indexInGroup: 6),
        78); // 70 + 8 + 0
  });

  test('matchPercent clamps to [70,99]', () {
    expect(
        matchPercent(
            product: prod(1, matched: []),
            flagged: <String>{},
            indexInGroup: 10),
        70);
  });

  test('productsForCondition filters by matched code, preserves order', () {
    final recs = [
      prod(1, matched: ['redness']),
      prod(2, matched: ['acne']),
      prod(3, matched: ['redness', 'oiliness']),
    ];
    expect(productsForCondition('redness', recs).map((p) => p.productId),
        [1, 3]);
  });

  test('brandsInResults: distinct non-empty, sorted', () {
    final recs = [
      prod(1, brand: 'Vichy'),
      prod(2, brand: 'Avene'),
      prod(3, brand: 'Vichy'),
      prod(4, brand: null),
    ];
    expect(brandsInResults(recs), ['Avene', 'Vichy']);
  });

  test('productViewsForCondition sorts by score desc by default', () {
    final recs = [
      prod(1, matched: ['redness']), // 83 @ index0
      prod(2, matched: ['redness', 'oiliness']), // 91 @ index1
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(),
    );
    expect(views.first.product.productId, 2); // highest match first
  });

  test('productViewsForCondition displayOrder keeps backend order', () {
    final recs = [
      prod(1, matched: ['redness', 'oiliness']),
      prod(2, matched: ['redness']),
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(sortBy: SortBy.displayOrder, sortDir: SortDir.asc),
    );
    expect(views.map((v) => v.product.productId), [1, 2]);
  });

  test('brand priority floats selected brands, stable within rank', () {
    final recs = [
      prod(1, brand: 'Avene', matched: ['redness']),
      prod(2, brand: 'Vichy', matched: ['redness']),
      prod(3, brand: 'Avene', matched: ['redness']),
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(
        sortBy: SortBy.displayOrder,
        sortDir: SortDir.asc,
        useAllBrands: false,
        priorityBrands: ['Vichy'],
      ),
    );
    expect(views.first.product.brand, 'Vichy');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/skin_derivations_products_test.dart`
Expected: FAIL — undefined `matchPercent`, `FilterState`, etc.

- [ ] **Step 3: Write minimal implementation**

Append to `frontend/lib/screens/skin_result/skin_derivations.dart`:

```dart

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/skin_derivations_products_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/skin_derivations.dart frontend/test/skin_result/skin_derivations_products_test.dart
git commit -m "feat(diag): dérivations produits/match/tri/filtre marques"
```

---

### Task 3: DiagnosticHero widget

**Files:**
- Create: `frontend/lib/screens/skin_result/diagnostic_hero.dart`
- Test: `frontend/test/skin_result/diagnostic_hero_test.dart`

**Interfaces:**
- Produces: `class DiagnosticHero extends StatelessWidget` with named params `{Key? key, File? frontPhoto, required String skinTypeLabel, int? globalScore, String? globalLabel, int? estimatedAge}`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/diagnostic_hero_test.dart`:

```dart
import 'package:analyse_faciale/screens/skin_result/diagnostic_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hero shows type, score, label and age (photo null fallback)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiagnosticHero(
          frontPhoto: null,
          skinTypeLabel: 'Mixte',
          globalScore: 82,
          globalLabel: 'Excellent',
          estimatedAge: 28,
        ),
      ),
    ));
    expect(find.text('Mixte'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.textContaining('28 ans'), findsOneWidget);
  });

  testWidgets('hero hides age row when age null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiagnosticHero(
          frontPhoto: null,
          skinTypeLabel: 'Grasse',
          globalScore: 60,
          globalLabel: 'Correct',
          estimatedAge: null,
        ),
      ),
    ));
    expect(find.textContaining('ans'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/diagnostic_hero_test.dart`
Expected: FAIL — can't resolve `diagnostic_hero.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/diagnostic_hero.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// En-tête du diagnostic : photo, type de peau, anneau de score global, âge.
class DiagnosticHero extends StatelessWidget {
  final File? frontPhoto;
  final String skinTypeLabel;
  final int? globalScore;
  final String? globalLabel;
  final int? estimatedAge;

  const DiagnosticHero({
    super.key,
    required this.frontPhoto,
    required this.skinTypeLabel,
    this.globalScore,
    this.globalLabel,
    this.estimatedAge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _photo(),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Votre type de peau',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      skinTypeLabel,
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _scoreRing(context),
          if (estimatedAge != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cake_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Âge de peau estimé · $estimatedAge ans',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _photo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: SizedBox(
        width: 72,
        height: 72,
        child: frontPhoto == null
            ? Container(
                color: AppColors.surface,
                child: const Icon(Icons.face_retouching_natural,
                    color: AppColors.primary, size: 34),
              )
            : Image.file(frontPhoto!, fit: BoxFit.cover),
      ),
    );
  }

  Widget _scoreRing(BuildContext context) {
    if (globalScore == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 128,
                height: 128,
                child: CircularProgressIndicator(
                  value: globalScore! / 100,
                  strokeWidth: 10,
                  backgroundColor: AppColors.surface,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$globalScore',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text('/100',
                      style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        if (globalLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            globalLabel!,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/diagnostic_hero_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/diagnostic_hero.dart frontend/test/skin_result/diagnostic_hero_test.dart
git commit -m "feat(diag): en-tête hero (photo, type, anneau score, âge)"
```

---

### Task 4: ProductCard + ProductDetailSheet

**Files:**
- Create: `frontend/lib/screens/skin_result/product_card.dart`
- Create: `frontend/lib/screens/skin_result/product_detail_sheet.dart`
- Test: `frontend/test/skin_result/product_card_test.dart`

**Interfaces:**
- Consumes: `ProductView` from `skin_derivations.dart`.
- Produces: `class ProductCard extends StatelessWidget` with `{Key? key, required ProductView view, required VoidCallback onTap, required VoidCallback onAdd}`; `class ProductDetailSheet extends StatelessWidget` with `{Key? key, required ProductView view, required List<String> matchedLabels, required VoidCallback onAdd}` plus `static Future<void> show(BuildContext context, {required ProductView view, required List<String> matchedLabels, required VoidCallback onAdd})`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/product_card_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/product_card.dart';
import 'package:analyse_faciale/screens/skin_result/product_detail_sheet.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProductView view() => const ProductView(
      product: ProductRecommendation(
        productId: 1,
        name: 'Crème hydratante',
        brand: 'Vichy',
        price: 28.95,
        reasonFr: 'Recommandé pour vos rougeurs.',
        matchedConditions: ['redness'],
      ),
      matchPercent: 91,
    );

void main() {
  testWidgets('ProductCard shows name, brand, price TND, match%, add button',
      (tester) async {
    var tapped = false;
    var added = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductCard(
          view: view(),
          onTap: () => tapped = true,
          onAdd: () => added = true,
        ),
      ),
    ));
    expect(find.text('Crème hydratante'), findsOneWidget);
    expect(find.text('Vichy'), findsOneWidget);
    expect(find.textContaining('28.950 TND'), findsOneWidget);
    expect(find.textContaining('91'), findsWidgets);
    await tester.tap(find.text('Ajouter'));
    expect(added, isTrue);
    await tester.tap(find.text('Crème hydratante'));
    expect(tapped, isTrue);
  });

  testWidgets('detail sheet shows reason and matched labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ProductDetailSheet.show(
              context,
              view: view(),
              matchedLabels: const ['Rougeurs et sensibilité'],
              onAdd: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recommandé pour vos rougeurs'), findsOneWidget);
    expect(find.text('Rougeurs et sensibilité'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/product_card_test.dart`
Expected: FAIL — can't resolve `product_card.dart` / `product_detail_sheet.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/product_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'skin_derivations.dart';

/// Vignette produit recommandé : image, match %, nom, marque, prix, « Ajouter ».
class ProductCard extends StatelessWidget {
  final ProductView view;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const ProductCard({
    super.key,
    required this.view,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final p = view.product;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            productThumb(p.imageUrl, 56),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.positiveLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${view.matchPercent}% Match',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (p.brand != null)
                    Text(p.brand!,
                        style: Theme.of(context).textTheme.bodySmall),
                  if (p.price != null)
                    Text(
                      '${p.price!.toStringAsFixed(3)} TND',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
              ),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniature produit partagée (réseau + repli icône).
Widget productThumb(String? imageUrl, double size) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
    child: SizedBox(
      width: size,
      height: size,
      child: imageUrl == null
          ? Container(
              color: AppColors.primaryLight,
              child: const Icon(Icons.spa_outlined, color: AppColors.primary),
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.primaryLight,
                child:
                    const Icon(Icons.spa_outlined, color: AppColors.primary),
              ),
            ),
    ),
  );
}
```

Create `frontend/lib/screens/skin_result/product_detail_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'product_card.dart' show productThumb;
import 'skin_derivations.dart';

/// Fiche détaillée produit (bottom sheet) : image, prix, match %, motifs.
class ProductDetailSheet extends StatelessWidget {
  final ProductView view;
  final List<String> matchedLabels;
  final VoidCallback onAdd;

  const ProductDetailSheet({
    super.key,
    required this.view,
    required this.matchedLabels,
    required this.onAdd,
  });

  static Future<void> show(
    BuildContext context, {
    required ProductView view,
    required List<String> matchedLabels,
    required VoidCallback onAdd,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductDetailSheet(
        view: view,
        matchedLabels: matchedLabels,
        onAdd: onAdd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = view.product;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: productThumb(p.imageUrl, 120)),
          const SizedBox(height: AppSpacing.md),
          Text(
            p.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (p.brand != null)
            Text(p.brand!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (p.price != null)
                Text(
                  '${p.price!.toStringAsFixed(3)} TND',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.positiveLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${view.matchPercent}% Match',
                    style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (matchedLabels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final label in matchedLabels)
                  Chip(
                    label: Text(label),
                    backgroundColor: AppColors.primaryLight,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Pourquoi ce produit',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(p.reasonFr,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('Ajouter'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/product_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/product_card.dart frontend/lib/screens/skin_result/product_detail_sheet.dart frontend/test/skin_result/product_card_test.dart
git commit -m "feat(diag): vignette produit + fiche détaillée (bottom sheet)"
```

---

### Task 5: severity_style + ConditionCard

**Files:**
- Create: `frontend/lib/screens/skin_result/severity_style.dart`
- Create: `frontend/lib/screens/skin_result/condition_card.dart`
- Test: `frontend/test/skin_result/condition_card_test.dart`

**Interfaces:**
- Consumes: `Severity`, `ProductView` from `skin_derivations.dart`; `ProductCard` from `product_card.dart`.
- Produces: `Color severityColor(Severity)`, `Color severityBg(Severity)` in `severity_style.dart`; `class ConditionCard extends StatelessWidget` with `{Key? key, required SkinCondition condition, required int health, required Severity severity, required bool expanded, required VoidCallback onToggle, required List<ProductView> products, required void Function(ProductView) onProductTap, required void Function(ProductView) onProductAdd}`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/condition_card_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/condition_card.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const condition = SkinCondition(
    code: 'redness',
    labelFr: 'Rougeurs et sensibilité',
    score: 28,
    severity: 'mild',
  );
  const products = [
    ProductView(
      product: ProductRecommendation(
        productId: 1,
        name: 'Crème apaisante',
        reasonFr: 'r',
        matchedConditions: ['redness'],
      ),
      matchPercent: 88,
    ),
  ];

  testWidgets('collapsed shows label, health/100 and reveal button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: false,
          onToggle: () {},
          products: products,
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.text('Rougeurs et sensibilité'), findsOneWidget);
    expect(find.textContaining('72/100'), findsOneWidget);
    expect(find.text('Trouver des produits'), findsOneWidget);
    expect(find.text('Crème apaisante'), findsNothing);
  });

  testWidgets('expanded reveals products and Masquer label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: true,
          onToggle: () {},
          products: products,
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.text('Masquer les produits'), findsOneWidget);
    expect(find.text('Crème apaisante'), findsOneWidget);
  });

  testWidgets('expanded with no products shows empty message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: true,
          onToggle: () {},
          products: const [],
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('Aucun produit correspondant'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/condition_card_test.dart`
Expected: FAIL — can't resolve `condition_card.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/severity_style.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'skin_derivations.dart';

/// Couleur d'accent d'une sévérité (pastille, texte).
Color severityColor(Severity s) {
  switch (s) {
    case Severity.faible:
      return AppColors.positive;
    case Severity.moderee:
      return const Color(0xFFE8973A);
    case Severity.marquee:
      return AppColors.negative;
  }
}

/// Couleur de fond douce d'une sévérité (pastille).
Color severityBg(Severity s) {
  switch (s) {
    case Severity.faible:
      return AppColors.positiveLight;
    case Severity.moderee:
      return const Color(0xFFFFF3E0);
    case Severity.marquee:
      return AppColors.negativeLight;
  }
}
```

Create `frontend/lib/screens/skin_result/condition_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../models/skin_analysis.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'product_card.dart';
import 'severity_style.dart';
import 'skin_derivations.dart';

/// Carte d'une condition prioritaire : score santé, sévérité, révélation produits.
class ConditionCard extends StatelessWidget {
  final SkinCondition condition;
  final int health;
  final Severity severity;
  final bool expanded;
  final VoidCallback onToggle;
  final List<ProductView> products;
  final void Function(ProductView) onProductTap;
  final void Function(ProductView) onProductAdd;

  const ConditionCard({
    super.key,
    required this.condition,
    required this.health,
    required this.severity,
    required this.expanded,
    required this.onToggle,
    required this.products,
    required this.onProductTap,
    required this.onProductAdd,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: severityBg(severity),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Priorité ${severityLabel(severity)}',
                  style: TextStyle(
                    color: severityColor(severity),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$health/100',
                style: TextStyle(
                  color: severityColor(severity),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            condition.labelFr,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: health / 100,
              minHeight: 8,
              color: severityColor(severity),
              backgroundColor: AppColors.divider,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: onToggle,
              child: Text(
                  expanded ? 'Masquer les produits' : 'Trouver des produits'),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            if (products.isEmpty)
              Text('Aucun produit correspondant en stock.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              ...products.map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ProductCard(
                    view: v,
                    onTap: () => onProductTap(v),
                    onAdd: () => onProductAdd(v),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/condition_card_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/severity_style.dart frontend/lib/screens/skin_result/condition_card.dart frontend/test/skin_result/condition_card_test.dart
git commit -m "feat(diag): carte condition + style sévérité + révélation produits"
```

---

### Task 6: ProductFilterBar

**Files:**
- Create: `frontend/lib/screens/skin_result/product_filter_bar.dart`
- Test: `frontend/test/skin_result/product_filter_bar_test.dart`

**Interfaces:**
- Consumes: `FilterState`, `SortBy`, `SortDir` from `skin_derivations.dart`.
- Produces: `class ProductFilterBar extends StatelessWidget` with `{Key? key, required bool expanded, required VoidCallback onToggleExpanded, required FilterState filter, required List<String> brands, required ValueChanged<FilterState> onChanged}`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/product_filter_bar_test.dart`:

```dart
import 'package:analyse_faciale/screens/skin_result/product_filter_bar.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed shows only header; expands on demand', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: false,
          onToggleExpanded: () {},
          filter: const FilterState(),
          brands: const ['Avene', 'Vichy'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Filtrer et trier les produits'), findsOneWidget);
    expect(find.text('Trier par'), findsNothing);
  });

  testWidgets('expanded exposes sort and brand toggle; emits change',
      (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: const FilterState(),
          brands: const ['Avene', 'Vichy'],
          onChanged: (f) => emitted = f,
        ),
      ),
    ));
    expect(find.text('Trier par'), findsOneWidget);
    expect(find.text('Utiliser toutes les marques'), findsOneWidget);
    // Toggle the "all brands" switch off.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.useAllBrands, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/product_filter_bar_test.dart`
Expected: FAIL — can't resolve `product_filter_bar.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/product_filter_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Panneau repliable de tri + priorité de marques pour les produits.
class ProductFilterBar extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final FilterState filter;
  final List<String> brands;
  final ValueChanged<FilterState> onChanged;

  const ProductFilterBar({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.filter,
    required this.brands,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Filtrer et trier les produits',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: AppSpacing.lg),
            Text('Trier par', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            DropdownButton<SortBy>(
              value: filter.sortBy,
              isExpanded: true,
              onChanged: (v) =>
                  onChanged(filter.copyWith(sortBy: v ?? filter.sortBy)),
              items: const [
                DropdownMenuItem(value: SortBy.score, child: Text('Score')),
                DropdownMenuItem(
                    value: SortBy.displayOrder,
                    child: Text("Ordre d'affichage")),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _dirButton(
                    'Décroissant',
                    filter.sortDir == SortDir.desc,
                    () => onChanged(filter.copyWith(sortDir: SortDir.desc)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _dirButton(
                    'Croissant',
                    filter.sortDir == SortDir.asc,
                    () => onChanged(filter.copyWith(sortDir: SortDir.asc)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(child: Text('Utiliser toutes les marques')),
                Switch(
                  value: filter.useAllBrands,
                  activeColor: AppColors.primary,
                  onChanged: (v) => onChanged(filter.copyWith(
                    useAllBrands: v,
                    priorityBrands: v ? const [] : filter.priorityBrands,
                  )),
                ),
              ],
            ),
            if (!filter.useAllBrands)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final b in brands)
                    FilterChip(
                      label: Text(b),
                      selected: filter.priorityBrands.contains(b),
                      selectedColor: AppColors.primaryLight,
                      onSelected: (sel) {
                        final next = [...filter.priorityBrands];
                        if (sel) {
                          next.add(b);
                        } else {
                          next.remove(b);
                        }
                        onChanged(filter.copyWith(priorityBrands: next));
                      },
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _dirButton(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primaryLight : null,
        side: BorderSide(
            color: selected ? AppColors.primary : AppColors.divider),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? AppColors.primaryDark : AppColors.textSecondary)),
    );
  }
}
```

Note: the brand search box from the spec is omitted here as YAGNI for the
typical short brand list; brands render as filter chips directly. If the list
grows long in practice, add a search field later.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/product_filter_bar_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/product_filter_bar.dart frontend/test/skin_result/product_filter_bar_test.dart
git commit -m "feat(diag): panneau filtre/tri + priorité marques"
```

---

### Task 7: ObservationCard + DetailedReport + RoutinePlaceholder

**Files:**
- Create: `frontend/lib/screens/skin_result/observation_card.dart`
- Create: `frontend/lib/screens/skin_result/detailed_report.dart`
- Create: `frontend/lib/screens/skin_result/routine_placeholder.dart`
- Test: `frontend/test/skin_result/report_widgets_test.dart`

**Interfaces:**
- Consumes: `Observation` from `skin_derivations.dart`; `SkinCondition`; `severity_style.dart`.
- Produces: `class ObservationCard extends StatelessWidget` `{Key? key, required Observation observation}`; `class DetailedReport extends StatelessWidget` `{Key? key, required List<SkinCondition> conditions, required bool expanded, required VoidCallback onToggle}`; `class RoutinePlaceholder extends StatelessWidget` `{Key? key, required VoidCallback onCreate}`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/report_widgets_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/detailed_report.dart';
import 'package:analyse_faciale/screens/skin_result/observation_card.dart';
import 'package:analyse_faciale/screens/skin_result/routine_placeholder.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ObservationCard renders forts and vigilance', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ObservationCard(
          observation: Observation(
            forts: ['Rides', 'Taches'],
            vigilance: ['Rougeurs'],
          ),
        ),
      ),
    ));
    expect(find.text('Observation'), findsOneWidget);
    expect(find.textContaining('Rides'), findsOneWidget);
    expect(find.textContaining('Rougeurs'), findsOneWidget);
  });

  testWidgets('ObservationCard empty renders nothing visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ObservationCard(
          observation: Observation(forts: [], vigilance: []),
        ),
      ),
    ));
    expect(find.text('Observation'), findsNothing);
  });

  testWidgets('DetailedReport toggles list', (tester) async {
    const conditions = [
      SkinCondition(
          code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailedReport(
          conditions: conditions,
          expanded: false,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.textContaining('1 critère'), findsOneWidget);
    expect(find.text('Voir plus'), findsOneWidget);
    expect(find.text('Rides'), findsNothing);
  });

  testWidgets('DetailedReport expanded shows rows', (tester) async {
    const conditions = [
      SkinCondition(
          code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailedReport(
          conditions: conditions,
          expanded: true,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.text('Rides'), findsOneWidget);
    expect(find.textContaining('92/100'), findsOneWidget);
  });

  testWidgets('RoutinePlaceholder fires onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutinePlaceholder(onCreate: () => created = true),
      ),
    ));
    expect(find.text('Créer ma routine'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Créer ma routine'));
    expect(created, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/report_widgets_test.dart`
Expected: FAIL — can't resolve the three new files.

- [ ] **Step 3: Write minimal implementation**

Create `frontend/lib/screens/skin_result/observation_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Synthèse dérivée : points forts (peau saine) et points à surveiller.
class ObservationCard extends StatelessWidget {
  final Observation observation;

  const ObservationCard({super.key, required this.observation});

  @override
  Widget build(BuildContext context) {
    if (observation.forts.isEmpty && observation.vigilance.isEmpty) {
      return const SizedBox.shrink();
    }
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search, color: AppColors.primary, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text('Observation',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          if (observation.forts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _line(
              color: AppColors.positive,
              symbol: '+',
              text: 'Points forts : ${observation.forts.join(', ')}.',
            ),
          ],
          if (observation.vigilance.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _line(
              color: AppColors.negative,
              symbol: '−',
              text: 'À surveiller : ${observation.vigilance.join(', ')}.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
      {required Color color, required String symbol, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(symbol,
            style: TextStyle(color: color, fontWeight: FontWeight.w900)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.textPrimary))),
      ],
    );
  }
}
```

Create `frontend/lib/screens/skin_result/detailed_report.dart`:

```dart
import 'package:flutter/material.dart';

import '../../models/skin_analysis.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'severity_style.dart';
import 'skin_derivations.dart';

/// Rapport détaillé repliable : tous les critères, score santé + sévérité.
class DetailedReport extends StatelessWidget {
  final List<SkinCondition> conditions;
  final bool expanded;
  final VoidCallback onToggle;

  const DetailedReport({
    super.key,
    required this.conditions,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = reportConditions(conditions);
    final n = ordered.length;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rapport détaillé',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'Évaluation basée sur $n ${n > 1 ? 'critères' : 'critère'} cutanés',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(expanded ? 'Voir moins' : 'Voir plus',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: AppSpacing.lg),
            for (final c in ordered) _row(context, c),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SkinCondition c) {
    final health = healthScore(c);
    final band = severityBand(c.score);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.labelFr,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
              ),
              Text('$health/100',
                  style: TextStyle(
                      color: severityColor(band),
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: health / 100,
              minHeight: 6,
              color: severityColor(band),
              backgroundColor: AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }
}
```

Create `frontend/lib/screens/skin_result/routine_placeholder.dart`:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Section « Créer ma routine » — teaser Matin/Soir (développée plus tard).
class RoutinePlaceholder extends StatelessWidget {
  final VoidCallback onCreate;

  const RoutinePlaceholder({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        children: [
          const Text(
            'Créer ma routine',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Matin / Soir · bientôt disponible',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
            ),
            child: const Text('Créer ma routine'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/report_widgets_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/observation_card.dart frontend/lib/screens/skin_result/detailed_report.dart frontend/lib/screens/skin_result/routine_placeholder.dart frontend/test/skin_result/report_widgets_test.dart
git commit -m "feat(diag): observation dérivée + rapport détaillé + placeholder routine"
```

---

### Task 8: SkinResultScreen shell + capture_flow wiring

**Files:**
- Modify: `frontend/lib/screens/skin_result_screen.dart` (full rewrite)
- Modify: `frontend/lib/capture/capture_flow.dart:72-79`
- Test: `frontend/test/skin_result/skin_result_screen_test.dart`

**Interfaces:**
- Consumes: all Task 1–7 widgets and derivations.
- Produces: `class SkinResultScreen extends StatefulWidget` with `{Key? key, required SkinAnalysisResult result, required VoidCallback onRetry, File? frontPhoto}`.

- [ ] **Step 1: Write the failing test**

Create `frontend/test/skin_result/skin_result_screen_test.dart`:

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SkinAnalysisResult sample() => const SkinAnalysisResult(
      analysisId: 1,
      skinType: 'combination',
      conditions: [
        SkinCondition(
            code: 'redness',
            labelFr: 'Rougeurs et sensibilité',
            score: 28,
            severity: 'mild'),
        SkinCondition(
            code: 'oiliness',
            labelFr: 'Excès de sébum',
            score: 40,
            severity: 'moderate'),
        SkinCondition(
            code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
      ],
      recommendations: [
        ProductRecommendation(
          productId: 1,
          name: 'Crème apaisante',
          brand: 'Vichy',
          price: 28.95,
          reasonFr: 'Pour vos rougeurs.',
          matchedConditions: ['oiliness'],
        ),
      ],
      disclaimerFr: 'Analyse indicative.',
      age: AgeInfo(estimatedAge: 28, messageFr: 'x'),
    );

void main() {
  testWidgets('renders hero, priority condition, reveals products',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SkinResultScreen(result: sample(), onRetry: () {}),
    ));
    // Skin type + age in hero.
    expect(find.text('Mixte'), findsOneWidget);
    expect(find.textContaining('28 ans'), findsOneWidget);
    // Priority condition card present (sébum score 40 => priority).
    expect(find.text('Excès de sébum'), findsOneWidget);

    // Reveal products for the sébum condition.
    await tester.tap(find.text('Trouver des produits').first);
    await tester.pumpAndSettle();
    expect(find.text('Crème apaisante'), findsOneWidget);
  });

  testWidgets('healthy-only result shows the peau saine state', (tester) async {
    final healthy = const SkinAnalysisResult(
      analysisId: 2,
      skinType: 'normal',
      conditions: [
        SkinCondition(
            code: 'wrinkles', labelFr: 'Rides', score: 5, severity: 'mild'),
      ],
      recommendations: [],
      disclaimerFr: 'x',
    );
    await tester.pumpWidget(MaterialApp(
      home: SkinResultScreen(result: healthy, onRetry: () {}),
    ));
    expect(find.textContaining('Peau globalement saine'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/skin_result_screen_test.dart`
Expected: FAIL — old `SkinResultScreen` renders differently (`find.text('Mixte')` may pass but `Trouver des produits` and `Peau globalement saine` are absent) → assertions fail.

- [ ] **Step 3: Write minimal implementation**

Replace the entire contents of `frontend/lib/screens/skin_result_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/skin_analysis.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';
import 'skin_result/condition_card.dart';
import 'skin_result/detailed_report.dart';
import 'skin_result/diagnostic_hero.dart';
import 'skin_result/observation_card.dart';
import 'skin_result/product_detail_sheet.dart';
import 'skin_result/product_filter_bar.dart';
import 'skin_result/routine_placeholder.dart';
import 'skin_result/skin_derivations.dart';

/// Diagnostic de peau — style Clinique premium, valeurs dérivées du résultat réel.
class SkinResultScreen extends StatefulWidget {
  final SkinAnalysisResult result;
  final VoidCallback onRetry;
  final File? frontPhoto;

  const SkinResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
    this.frontPhoto,
  });

  @override
  State<SkinResultScreen> createState() => _SkinResultScreenState();
}

class _SkinResultScreenState extends State<SkinResultScreen> {
  static const _skinTypeLabels = {
    'oily': 'Grasse',
    'dry': 'Sèche',
    'combination': 'Mixte',
    'normal': 'Normale',
  };

  FilterState _filter = const FilterState();
  final Set<String> _expanded = {};
  bool _filterExpanded = false;
  bool _reportExpanded = false;

  void _stub(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, String> get _labelByCode =>
      {for (final c in widget.result.conditions) c.code: c.labelFr};

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final flagged = flaggedCodes(result.conditions);
    final priorities = priorityConditions(result.conditions);
    final gScore = globalScore(result.conditions);
    final brands = brandsInResults(result.recommendations);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(title: 'Diagnostic de peau'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DiagnosticHero(
                    frontPhoto: widget.frontPhoto,
                    skinTypeLabel:
                        _skinTypeLabels[result.skinType] ?? result.skinType,
                    globalScore: gScore,
                    globalLabel: gScore == null ? null : globalLabel(gScore),
                    estimatedAge: result.age?.estimatedAge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ObservationCard(
                      observation: deriveObservation(result.conditions)),
                  const SizedBox(height: AppSpacing.md),
                  ProductFilterBar(
                    expanded: _filterExpanded,
                    onToggleExpanded: () => setState(
                        () => _filterExpanded = !_filterExpanded),
                    filter: _filter,
                    brands: brands,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (priorities.isEmpty)
                    _healthyState(context)
                  else
                    ...priorities.map((c) {
                      final views = productViewsForCondition(
                        code: c.code,
                        recs: result.recommendations,
                        flagged: flagged,
                        filter: _filter,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ConditionCard(
                          condition: c,
                          health: healthScore(c),
                          severity: severityBand(c.score),
                          expanded: _expanded.contains(c.code),
                          onToggle: () => setState(() {
                            _expanded.contains(c.code)
                                ? _expanded.remove(c.code)
                                : _expanded.add(c.code);
                          }),
                          products: views,
                          onProductTap: (v) => ProductDetailSheet.show(
                            context,
                            view: v,
                            matchedLabels: [
                              for (final code in v.product.matchedConditions)
                                _labelByCode[code] ?? code,
                            ],
                            onAdd: () => _stub('Bientôt : ajout au panier'),
                          ),
                          onProductAdd: (_) =>
                              _stub('Bientôt : ajout au panier'),
                        ),
                      );
                    }),
                  DetailedReport(
                    conditions: result.conditions,
                    expanded: _reportExpanded,
                    onToggle: () =>
                        setState(() => _reportExpanded = !_reportExpanded),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  RoutinePlaceholder(
                    onCreate: () => _stub('Bientôt : création de routine'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (result.disclaimerFr.isNotEmpty)
                    Text(
                      result.disclaimerFr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  CustomButton(
                    label: 'Refaire la capture',
                    icon: Icons.refresh,
                    onPressed: widget.onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _healthyState(BuildContext context) {
    return CustomCard(
      child: Row(
        children: [
          const Icon(Icons.verified_outlined,
              color: AppColors.positive, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Peau globalement saine — aucune préoccupation prioritaire détectée.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Modify capture_flow to pass the front photo**

In `frontend/lib/capture/capture_flow.dart`, change the `SkinResultScreen`
construction (currently lines 74-77) to pass the captured front photo:

```dart
              builder: (_) => SkinResultScreen(
                result: result,
                frontPhoto: front,
                onRetry: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
```

(`front` is the non-null `File` already computed at the top of `_startAnalysis`.)

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/skin_result/skin_result_screen_test.dart`
Expected: PASS (2 tests).

Run: `flutter test`
Expected: PASS (all suites, including the pre-existing `skin_analysis_test.dart`).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/skin_result_screen.dart frontend/lib/capture/capture_flow.dart frontend/test/skin_result/skin_result_screen_test.dart
git commit -m "feat(diag): écran diagnostic Clinique premium (shell + wiring photo)"
```

---

## Self-Review

**1. Spec coverage:**
- Hero (photo/type/score ring/age) → Task 3 + Task 8 wiring ✅
- Observation (derived) → Task 1 (`deriveObservation`) + Task 7 (`ObservationCard`) ✅
- Filter/sort (score/display order, direction, brand priority) → Task 2 (logic) + Task 6 (UI) ✅
- Per-condition cards + `Trouver des produits` reveal → Task 5 + Task 8 ✅
- Products per condition + match % → Task 2 ✅
- Product card (image/name/brand/price TND/match%) + detail sheet → Task 4 ✅
- Detailed report (all conditions, health desc) → Task 1 (`reportConditions`) + Task 7 ✅
- Routine placeholder (stub) → Task 7 ✅
- `Ajouter` / `Créer ma routine` stubs (SnackBar) → Task 8 ✅
- Health-score flip, severity bands, global bands, priority threshold → Task 1 ✅
- Brands from results (no catalog), expiration/EAN/description deferred → honored (not built) ✅
- Front photo threaded through capture_flow → Task 8 ✅
- Empty/healthy state, empty-products message, null-photo fallback → Task 8 / Task 5 / Task 3 ✅

**2. Placeholder scan:** No TBD/TODO; every code step contains complete code; every test step contains full test bodies. The Task 6 note about the omitted brand search is a deliberate YAGNI decision, not a placeholder.

**3. Type consistency:** `ProductView{product, matchPercent}`, `FilterState{sortBy, sortDir, useAllBrands, priorityBrands}`, `Severity{faible,moderee,marquee}`, `Observation{forts,vigilance}`, and all widget constructor params are used identically across Tasks 2–8. `productViewsForCondition` signature matches its call site in Task 8. `SkinResultScreen(result, onRetry, frontPhoto?)` matches the capture_flow call. `productThumb` is defined once in `product_card.dart` and imported by `product_detail_sheet.dart`.

**Deviation from spec (noted):** the brand search box inside the filter panel is omitted (YAGNI for short brand lists); brands render directly as filter chips. Everything else follows the spec.
