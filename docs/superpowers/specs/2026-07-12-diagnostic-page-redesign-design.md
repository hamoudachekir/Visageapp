# Diagnostic Page Redesign — Design Spec

**Date:** 2026-07-12
**Branch:** designe
**Scope:** Frontend (Flutter) only. No backend/DB/schema changes.

## Goal

Rebuild the skin diagnostic result screen (`SkinResultScreen`) in a fresh
"Clinique premium (soft & airy)" visual style, keeping the information
architecture of the reference screenshots (hero + skin type, global score,
skin age, observation, product filter/sort, per-condition cards that reveal
matching products, product detail sheet, detailed report, routine
placeholder). Every value on screen is derived from **today's real
`POST /v1/skin/analyze` response** — nothing is faked. Features that need
data the backend does not return are deferred (hidden) or stubbed.

## Decisions (locked with user)

1. **Data strategy:** frontend-only — derive what's derivable, defer the rest.
2. **Visual direction:** Clinique premium — light/airy, soft rounded cards,
   circular score ring, pastel severity chips, Lumina teal brand.

## Source data (ground truth)

`SkinAnalysisResult` (`frontend/lib/models/skin_analysis.dart`), parsed from
`SkinAnalyzeResponse` (`backend/app/skin/schemas.py`):

- `analysisId: int`
- `skinType: String` — `oily | dry | combination | normal`
- `conditions: List<SkinCondition>` — each `{code, labelFr, score 0..100,
  severity mild|moderate|severe, zones}`. **`score` = severity of the
  condition (higher = worse).**
- `recommendations: List<ProductRecommendation>` — each `{productId, name,
  brand?, price?, imageUrl?, reasonFr, matchedConditions[]}`. Backend returns
  them pre-sorted best-first; `matchedConditions` excludes `skin_type_*`.
- `age: AgeInfo?` — `{estimatedAge, realAge?, skinAgeDelta?, messageFr}`
- `disclaimerFr: String`

The captured **front photo** (`File`) exists in `capture_flow.dart`
(`_startAnalysis` → `front`) but is not currently passed to the screen. This
spec threads it through for the hero.

## Derivations (pure, unit-tested)

All in `frontend/lib/screens/skin_result/skin_derivations.dart`.

### Health score (per condition)
`health(c) = 100 - c.score`. Higher = healthier. This is the `xx/100` shown
on condition cards and the report. (Backend raw `score` = severity.)

### Severity band + French label (from RAW score)
- `score < 30` → **faible** (positive/green)
- `30 ≤ score < 60` → **modérée** (orange/warning)
- `score ≥ 60` → **marquée** (negative/red)

Pill text: `Priorité faible` / `Priorité modérée` / `Priorité marquée`.
Report tag text: `Faible` / `Modérée` / `Marquée`.

### Global score + label
`global = round(mean(health(c) for c in all conditions))` (all conditions,
including healthy ones). Empty → `null` (hide ring, show neutral state).
Label bands:
- `≥ 80` → **Excellent**
- `65–79` → **Bon**
- `50–64` → **Correct**
- `< 50` → **À améliorer**

### Priority conditions (cards that show products)
Conditions with **raw `score ≥ 30`** (backend `RECOMMEND_THRESHOLD`), sorted
by raw score **descending** (worst first).

### Products per condition
Group `recommendations` where `matchedConditions` contains the condition
`code`. Order within a group preserves backend order (best-first).

### Match % (per product, per condition group)
```
flagged   = { c.code : c in conditions, c.score >= 30 }        // Set
covered   = | product.matchedConditions ∩ flagged |
coverage  = covered / max(1, |flagged|)                        // 0..1
rankBonus = max(0, 5 - indexInConditionGroup)                  // first=+5..sixth+=0
match%    = clamp( round(70 + 25*coverage + rankBonus), 70, 99 )
```
Deterministic; products addressing more of the user's concerns rank higher.

### Brands present
`brandsInResults = distinct non-null brands across recommendations`, sorted
alphabetically. This backs the brand-priority filter (no global catalog).

## Filter / sort (state in the screen shell)

`ProductFilterBar` — collapsible "Filtrer et trier les produits" panel:

- **Sort by:** `Score` (match %, default) · `Ordre d'affichage` (backend order).
  Direction toggle: `Décroissant` (default) / `Croissant`.
  (Sort-by-expiration is **deferred** — no data — and omitted.)
- **Marques prioritaires:** toggle `Utiliser toutes les marques`. When off,
  user selects/searches priority brands from `brandsInResults`; selected
  brands' products float to the top of each condition group. Search box
  filters the chip list.

Filter/sort applies to the product lists revealed inside each condition card.

## Screen layout (top → bottom)

1. **DiagnosticHero** — soft card, teal tint: front photo (fallback gradient +
   skin-type icon when photo is null), skin-type label (`Mixte/Grasse/Sèche/
   Normale`), circular **score ring** (value `global/100`, center number +
   `/100`, label below), skin-age row `🎂 Âge de peau estimé · {estimatedAge}
   ans` (only when `age != null`).
2. **ObservationCard** (derived-light): `Points forts` = up to 4 healthy
   condition labels (raw score < 30, highest health first); `À surveiller` =
   flagged condition labels (raw score ≥ 30). No faked prose.
3. **ProductFilterBar** (collapsible).
4. **Condition cards** (priority conditions): label, `health/100`, severity
   pill, thin progress bar (value = health/100), `Trouver des produits` →
   expands to the product list (`Masquer les produits` to collapse). Empty
   group → `Aucun produit correspondant en stock.`
5. **DetailedReport**: expandable `Voir plus / Voir moins`; header
   `Évaluation basée sur {N} critères cutanés`; expanded shows **all**
   conditions sorted by health **descending**, each with label, `health/100`,
   severity tag, zones (if any). No prose descriptions (deferred).
6. **RoutinePlaceholder**: `Créer ma routine` card with Matin/Soir teaser,
   marked "bientôt"; stub button.

Disclaimer (`disclaimerFr`) shown as a subtle footer note. `Refaire la
capture` action preserved (retry).

## Real / deferred / stubbed

- **Real & wired:** hero photo, skin type, global score ring, skin age,
  per-condition health + severity, per-condition product reveal, product
  cards (image/name/brand/price **TND**/match %), product detail sheet
  (image, price, match %, matched-condition chips, `reasonFr`), detailed
  report (all conditions), sort (match / display order), brand-priority
  filter (brands in results).
- **Derived-light:** Observation block (points forts / à surveiller from
  scores).
- **Deferred (hidden):** product EAN, expiration date, description bullets;
  sort-by-expiration; full brand catalog; per-condition prose descriptions.
- **Stubbed (button present, callback no-op for now):** `Ajouter` on product
  cards; `Créer ma routine`. No cart/routine system exists yet.

## Product detail sheet

Modal bottom sheet (`ProductDetailSheet`): large image (network, fallback
icon), name, brand, price `{price.toStringAsFixed(3)} TND`, match % badge,
matched-condition chips (French labels), `reasonFr` ("Pourquoi ce produit").
`Ajouter` stub at the bottom. Deferred fields hidden.

## Architecture & files

Rewrite the screen as a small **stateful** shell holding UI state (filter/sort
selection, expanded condition codes, report-expanded flag) with focused
sub-widgets and pure derivation functions.

- **Modify** `frontend/lib/screens/skin_result_screen.dart` — stateful shell.
- **Modify** `frontend/lib/capture/capture_flow.dart` — pass `frontPhoto: front`
  into `SkinResultScreen` (new **optional** `File? frontPhoto`, default null,
  so any other caller stays compatible).
- **Create** `frontend/lib/screens/skin_result/`:
  - `skin_derivations.dart` — pure logic + small view-models
    (`ConditionView`, `ProductView`, `DiagnosticSummary`).
  - `diagnostic_hero.dart`
  - `observation_card.dart`
  - `product_filter_bar.dart` (+ `FilterState`, `SortBy`, `SortDir`)
  - `condition_card.dart`
  - `product_card.dart`
  - `product_detail_sheet.dart`
  - `detailed_report.dart`
  - `routine_placeholder.dart`
- **Create** `frontend/test/skin_result/` — unit tests for derivations +
  widget smoke tests.

Style tokens: `AppColors.primary 0xFF0C7C84`, `background 0xFFF8F9FF`,
`AppColors.cardShadow`, `AppSpacing.radiusLg`, 8-pt spacing, severity chips
via `positiveLight` / `negativeLight` / orange.

## Error / empty states

- Analysis failure (`result.ok == false` at the `AnalysisResult` layer is a
  separate screen; here we always receive a successful `SkinAnalysisResult`).
- **No priority conditions** (all healthy): show a positive "Peau globalement
  saine" state in place of condition cards; still show global score + report.
- **No recommendations for a condition:** card shows
  `Aucun produit correspondant en stock.`
- **`frontPhoto == null`** (web/replay from history): hero uses gradient +
  skin-type icon, no crash.
- **Network image error:** fallback icon (existing `errorBuilder` pattern).

## Testing

- **Unit** (`skin_derivations`): `health`, `globalScore` + label bands,
  `severityBand` + labels, `matchPercent` (coverage + rank bonus + clamp),
  `groupByCondition`, `brandsInResults`, sort (match/display × dir, brand
  priority float).
- **Widget smoke:** screen renders from a sample `SkinAnalysisResult`;
  tapping `Trouver des produits` reveals product cards; tapping a product
  opens the detail sheet; changing sort reorders products; healthy-only
  result shows the "peau saine" state.

## Out of scope

Backend/DB changes, routine engine, ordering/cart, brand catalog, observation
NLP text, expanded 14-parameter model. These are future work.
