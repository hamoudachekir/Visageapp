# Full Filter + Brand Catalog + Description Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real brand catalog + product description to the API and rebuild `ProductFilterBar` into the full-fidelity filter (search + catalog add + priority reorder/remove/clear), with product description in the detail sheet.

**Architecture:** Backend adds `GET /v1/skin/brands` and threads the existing `description` column into recommendations. Frontend adds the model field, an API client method, a redesigned stateful `ProductFilterBar`, a description section in the detail sheet, and screen/capture-flow wiring that fetches the catalog. No DB migration (columns already exist).

**Tech Stack:** FastAPI + SQLAlchemy + Pydantic v2 (backend); Flutter/Dart package `analyse_faciale` (frontend). No new dependencies.

## Global Constraints

- Backend: FastAPI sync SQLAlchemy, Pydantic v2. Endpoints under `/v1/skin`. Same JWT auth as `/analyze` (`Depends(auth_module.get_current_pharmacy)`). No DB migration.
- `GET /v1/skin/brands` → `{"brands": [...]}`: distinct, non-null, non-blank, **active** product brands, sorted alphabetically.
- `description` (existing `VisageProduct.description` column) threaded through `Recommendation` → `fetch_products` → `build_recommendations` → `RecommendationOut` → router; no scoring/ranking change.
- Frontend package `analyse_faciale`; French UI copy; `flutter` commands run from `frontend/`.
- `ProductFilterBar` is presentational for the FilterState (emits via `onChanged`); it may hold ONLY the ephemeral search text as local state. New prop `List<String> catalog` replaces `brands`.
- Brand add → append to `priorityBrands` + `useAllBrands=false`. Clear-all → `priorityBrands=[]` + `useAllBrands=true`. Reorder/remove emit updated `priorityBrands`. The catalog + search are shown whenever the panel is expanded (independent of `useAllBrands`).
- Sort options: `Score`, `Ordre d'affichage` only (no expiration). Switch uses `activeThumbColor` (SDK floor is `>=3.32.0`).
- `SkinResultScreen.brandCatalog` is an optional `List<String>` (default `const []`); catalog used = `brandCatalog.isNotEmpty ? brandCatalog : brandsInResults(recommendations)`. The screen performs NO network (stays testable); `capture_flow` fetches the catalog.
- TDD, frequent commits. Backend: `python -m pytest` from `backend/`. Frontend: `flutter test` + `flutter analyze` from `frontend/` (must stay clean).

---

## File Structure

- Modify `backend/app/skin/schemas.py` — add `BrandsResponse`; add `description` to `RecommendationOut`.
- Modify `backend/app/skin/router.py` — add `GET /v1/skin/brands`; map `description` into `RecommendationOut`.
- Modify `backend/app/skin/recommend.py` — `description` in `Recommendation`, `fetch_products`, `build_recommendations`.
- Modify `backend/tests/test_skin_endpoint.py`, `backend/tests/test_recommend.py`.
- Modify `frontend/lib/models/skin_analysis.dart` — `ProductRecommendation.description`.
- Modify `frontend/lib/services/skin_api.dart` — `fetchBrands()`.
- Rewrite `frontend/lib/screens/skin_result/product_filter_bar.dart` — full redesign.
- Modify `frontend/lib/screens/skin_result/product_detail_sheet.dart` — description section.
- Modify `frontend/lib/screens/skin_result_screen.dart` + `frontend/lib/capture/capture_flow.dart` — catalog wiring.
- Tests under `frontend/test/skin_result/`.

---

### Task 1: Backend — `GET /v1/skin/brands`

**Files:**
- Modify: `backend/app/skin/schemas.py`
- Modify: `backend/app/skin/router.py`
- Test: `backend/tests/test_skin_endpoint.py`

**Interfaces:**
- Produces: `GET /v1/skin/brands` → `BrandsResponse{brands: list[str]}`.

- [ ] **Step 1: Write the failing test**

Append to `backend/tests/test_skin_endpoint.py`:

```python
def test_brands_liste_triee(api):
    client, _ = api
    res = client.get("/v1/skin/brands")
    assert res.status_code == 200
    assert res.json()["brands"] == ["A", "B"]


def test_brands_exclut_inactifs_null_et_vides(api):
    client, Session = api
    s = Session()
    s.add_all([
        VisageProduct(id=3, name="X", brand="A", price=1, in_stock=True, active=False),
        VisageProduct(id=4, name="Y", brand=None, price=1, in_stock=True, active=True),
        VisageProduct(id=5, name="Z", brand="  ", price=1, in_stock=True, active=True),
        VisageProduct(id=6, name="W", brand="Cerave", price=1, in_stock=True, active=True),
    ])
    s.commit()
    s.close()
    res = client.get("/v1/skin/brands")
    assert res.json()["brands"] == ["A", "B", "Cerave"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py::test_brands_liste_triee -q`
Expected: FAIL (404 — route not defined).

- [ ] **Step 3: Implement**

In `backend/app/skin/schemas.py` add:

```python
class BrandsResponse(BaseModel):
    brands: list[str]
```

In `backend/app/skin/router.py`:
- Add `VisageProduct` to the models import: change `from ..models import Client, Pharmacy, SkinAnalysis` to `from ..models import Client, Pharmacy, SkinAnalysis, VisageProduct`.
- Add `BrandsResponse` to the schemas import line.
- Add the route (place it after the `analyze_skin` function):

```python
@router.get("/v1/skin/brands", response_model=BrandsResponse)
def list_brands(
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> BrandsResponse:
    """Marques distinctes des produits actifs (catalogue du filtre)."""
    rows = (
        db.query(VisageProduct.brand)
        .filter(VisageProduct.active.is_(True), VisageProduct.brand.isnot(None))
        .distinct()
        .all()
    )
    brands = sorted({r[0].strip() for r in rows if r[0] and r[0].strip()})
    return BrandsResponse(brands=brands)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py -q`
Expected: PASS (all, including the two new).

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/schemas.py backend/app/skin/router.py backend/tests/test_skin_endpoint.py
git commit -m "feat(skin): GET /v1/skin/brands (catalogue marques actives)"
```

---

### Task 2: Backend — `description` in recommendations

**Files:**
- Modify: `backend/app/skin/recommend.py`
- Modify: `backend/app/skin/schemas.py`
- Modify: `backend/app/skin/router.py`
- Test: `backend/tests/test_recommend.py`, `backend/tests/test_skin_endpoint.py`

**Interfaces:**
- Produces: `Recommendation.description: str | None`; `RecommendationOut.description: str | None`; response `recommendations[i].description`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/tests/test_recommend.py`:

```python
def test_recommendation_inclut_description():
    scores = {"acne": 62}
    mappings = [{
        "condition_code": "acne", "product_id": 1, "priority": 5,
        "skin_type": None, "min_age": None, "max_age": None,
    }]
    products = {1: {
        "name": "Gel", "brand": "A", "price": 10.0, "image_url": None,
        "description": "Nettoie en douceur.", "in_stock": True, "active": True,
    }}
    recs = build_recommendations(scores, "oily", mappings, products)
    assert recs[0].description == "Nettoie en douceur."
```

(If `build_recommendations` is not already imported at the top of `test_recommend.py`, add `from app.skin.recommend import build_recommendations`.)

Append to `backend/tests/test_skin_endpoint.py`:

```python
def test_description_dans_reco(api):
    client, Session = api
    s = Session()
    p = s.get(VisageProduct, 1)
    p.description = "Nettoie en douceur."
    s.commit()
    s.close()
    res = client.post("/v1/skin/analyze", files=_files())
    reco = res.json()["recommendations"][0]
    assert reco["description"] == "Nettoie en douceur."
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && python -m pytest tests/test_recommend.py::test_recommendation_inclut_description tests/test_skin_endpoint.py::test_description_dans_reco -q`
Expected: FAIL (`AttributeError: description` / `KeyError`).

- [ ] **Step 3: Implement**

In `backend/app/skin/recommend.py`:
- `Recommendation` dataclass: add field `description: str | None` (after `image_url`).
- `fetch_products` returned dict: add `"description": r.description,`.
- `build_recommendations`, in the `Recommendation(...)` construction: add `description=product.get("description"),` (after `image_url=...`).

In `backend/app/skin/schemas.py`, `RecommendationOut`: add `description: str | None = None` (after `image_url`).

In `backend/app/skin/router.py`, the `RecommendationOut(...)` mapping: add `description=r.description,`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && python -m pytest tests/test_recommend.py tests/test_skin_endpoint.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/recommend.py backend/app/skin/schemas.py backend/app/skin/router.py backend/tests/test_recommend.py backend/tests/test_skin_endpoint.py
git commit -m "feat(skin): description produit dans les recommandations"
```

---

### Task 3: Frontend — `ProductRecommendation.description`

**Files:**
- Modify: `frontend/lib/models/skin_analysis.dart`
- Test: `frontend/test/skin_analysis_test.dart`

**Interfaces:**
- Produces: `ProductRecommendation.description: String?`.

- [ ] **Step 1: Write the failing test**

Append to `frontend/test/skin_analysis_test.dart` (inside `main()`):

```dart
  test('ProductRecommendation parse la description', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [
        {
          'product_id': 7,
          'name': 'Gel',
          'reason_fr': 'r',
          'description': 'Nettoie en douceur.',
          'matched_conditions': [],
        },
      ],
      'disclaimer_fr': 'x',
    };
    final result = SkinAnalysisResult.fromJson(json);
    expect(result.recommendations.single.description, 'Nettoie en douceur.');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_analysis_test.dart`
Expected: FAIL (`description` getter not defined).

- [ ] **Step 3: Implement**

In `frontend/lib/models/skin_analysis.dart`, `ProductRecommendation`:
- Add field: `final String? description;`
- Add to the const constructor: `this.description,`
- In `fromJson`: `description: json['description'] as String?,`

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_analysis_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/models/skin_analysis.dart frontend/test/skin_analysis_test.dart
git commit -m "feat(diag): ProductRecommendation.description"
```

---

### Task 4: Frontend — `SkinApi.fetchBrands()`

**Files:**
- Modify: `frontend/lib/services/skin_api.dart`

**Interfaces:**
- Produces: `Future<List<String>> SkinApi.fetchBrands()` — `GET /v1/skin/brands`, returns `[]` on any error.

- [ ] **Step 1: Implement**

In `frontend/lib/services/skin_api.dart`, add this method to the `SkinApi` class (after `analyze`):

```dart
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
```

(No new imports needed: `http`, `jsonDecode`, `utf8` are already imported in this file.)

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/services/skin_api.dart`
Expected: `No issues found!`

(No unit test: this is a thin HTTP wrapper with a graceful catch; it is exercised end-to-end via the app. Covered by the analyzer.)

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/skin_api.dart
git commit -m "feat(diag): SkinApi.fetchBrands (catalogue marques)"
```

---

### Task 5: Frontend — ProductFilterBar redesign

**Files:**
- Rewrite: `frontend/lib/screens/skin_result/product_filter_bar.dart`
- Modify: `frontend/lib/screens/skin_result_screen.dart` (call-site rename only — keeps the app compiling)
- Test: `frontend/test/skin_result/product_filter_bar_test.dart` (replace)

**Interfaces:**
- Consumes: `FilterState`, `SortBy`, `SortDir` from `skin_derivations.dart`.
- Produces: `class ProductFilterBar extends StatefulWidget` with `{Key? key, required bool expanded, required VoidCallback onToggleExpanded, required FilterState filter, required List<String> catalog, required ValueChanged<FilterState> onChanged}`.

**IMPORTANT (cross-task compile):** This task renames the `brands` prop to `catalog`. The screen shell (`skin_result_screen.dart`) currently calls `ProductFilterBar(... brands: brands ...)`, which will NOT compile after the rename. In Step 3 you MUST also update that call site to `catalog: brands` (keep the existing `final brands = brandsInResults(...)` local for now — Task 7 replaces it). Then the full suite compiles and passes at this task's boundary.

- [ ] **Step 1: Write the failing test**

Replace the entire contents of `frontend/test/skin_result/product_filter_bar_test.dart` with:

```dart
import 'package:analyse_faciale/screens/skin_result/product_filter_bar.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required FilterState filter,
  required List<String> catalog,
  ValueChanged<FilterState>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: filter,
          catalog: catalog,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('collapsed shows only header', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: false,
          onToggleExpanded: () {},
          filter: const FilterState(),
          catalog: const ['Avene', 'Vichy'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Filtrer et trier les produits'), findsOneWidget);
    expect(find.text('Marques prioritaires'), findsNothing);
  });

  testWidgets('expanded shows sort, brand section, search', (tester) async {
    await tester.pumpWidget(_host(
        filter: const FilterState(), catalog: const ['Avene', 'Vichy']));
    expect(find.text('Trier les produits par'), findsOneWidget);
    expect(find.text('Marques prioritaires'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('tapping a catalog chip adds brand as priority', (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    await tester.tap(find.text('Vichy'));
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, ['Vichy']);
    expect(emitted!.useAllBrands, isFalse);
  });

  testWidgets('search filters catalog chips', (tester) async {
    await tester.pumpWidget(_host(
        filter: const FilterState(), catalog: const ['Avene', 'Vichy']));
    expect(find.text('Avene'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'vic');
    await tester.pump();
    expect(find.text('Avene'), findsNothing);
    expect(find.text('Vichy'), findsOneWidget);
  });

  testWidgets('clear-all empties priority and turns useAllBrands on',
      (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(useAllBrands: false, priorityBrands: ['Vichy']),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    expect(find.text('Marques sélectionnées (Ordre de priorité)'),
        findsOneWidget);
    await tester.tap(find.text('Tout effacer'));
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, isEmpty);
    expect(emitted!.useAllBrands, isTrue);
  });

  testWidgets('reorder moves a selected brand up', (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(
          useAllBrands: false, priorityBrands: ['Vichy', 'Avene']),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, ['Avene', 'Vichy']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/product_filter_bar_test.dart`
Expected: FAIL (constructor no longer has `brands`; `catalog` undefined until rewrite).

- [ ] **Step 3: Rewrite the widget**

Replace the entire contents of `frontend/lib/screens/skin_result/product_filter_bar.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/custom_card.dart';
import 'skin_derivations.dart';

/// Panneau repliable : tri + catalogue de marques (recherche, priorité, ordre).
class ProductFilterBar extends StatefulWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final FilterState filter;
  final List<String> catalog;
  final ValueChanged<FilterState> onChanged;

  const ProductFilterBar({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.filter,
    required this.catalog,
    required this.onChanged,
  });

  @override
  State<ProductFilterBar> createState() => _ProductFilterBarState();
}

class _ProductFilterBarState extends State<ProductFilterBar> {
  String _search = '';

  FilterState get _filter => widget.filter;
  void _emit(FilterState f) => widget.onChanged(f);

  void _addBrand(String brand) {
    if (_filter.priorityBrands.contains(brand)) return;
    _emit(_filter.copyWith(
      priorityBrands: [..._filter.priorityBrands, brand],
      useAllBrands: false,
    ));
  }

  void _removeBrand(String brand) {
    _emit(_filter.copyWith(
        priorityBrands: [..._filter.priorityBrands]..remove(brand)));
  }

  void _clearBrands() =>
      _emit(_filter.copyWith(priorityBrands: const [], useAllBrands: true));

  void _move(int index, int delta) {
    final next = [..._filter.priorityBrands];
    final target = index + delta;
    if (target < 0 || target >= next.length) return;
    next.insert(target, next.removeAt(index));
    _emit(_filter.copyWith(priorityBrands: next));
  }

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onToggleExpanded,
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text('Filtrer et trier les produits',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                ),
                Icon(widget.expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
          if (widget.expanded) ...[
            const Divider(height: AppSpacing.lg),
            _sortSection(context),
            const SizedBox(height: AppSpacing.md),
            _brandSection(context),
          ],
        ],
      ),
    );
  }

  Widget _sortSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trier les produits par',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        DropdownButton<SortBy>(
          value: _filter.sortBy,
          isExpanded: true,
          onChanged: (v) => _emit(_filter.copyWith(sortBy: v ?? _filter.sortBy)),
          items: const [
            DropdownMenuItem(value: SortBy.score, child: Text('Score')),
            DropdownMenuItem(
                value: SortBy.displayOrder, child: Text("Ordre d'affichage")),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _dirButton('Décroissant', _filter.sortDir == SortDir.desc,
                  () => _emit(_filter.copyWith(sortDir: SortDir.desc))),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _dirButton('Croissant', _filter.sortDir == SortDir.asc,
                  () => _emit(_filter.copyWith(sortDir: SortDir.asc))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _brandSection(BuildContext context) {
    final selected = _filter.priorityBrands;
    final query = _search.trim().toLowerCase();
    final filtered = widget.catalog
        .where((b) => query.isEmpty || b.toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Marques prioritaires',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Text('Utiliser toutes les marques',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Switch(
              value: _filter.useAllBrands,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => _emit(_filter.copyWith(
                useAllBrands: v,
                priorityBrands: v ? const [] : _filter.priorityBrands,
              )),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: 'Rechercher des marques...',
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text('Marques sélectionnées (Ordre de priorité)',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                  onPressed: _clearBrands, child: const Text('Tout effacer')),
            ],
          ),
          for (var i = 0; i < selected.length; i++)
            _selectedRow(i, selected[i]),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Ajouter plus de marques',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (final brand in filtered)
              _catalogChip(brand, selected.contains(brand)),
          ],
        ),
      ],
    );
  }

  Widget _selectedRow(int index, String brand) {
    final last = index == _filter.priorityBrands.length - 1;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Text('${index + 1}',
              style: const TextStyle(
                  color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(brand,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: index == 0 ? null : () => _move(index, -1),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: last ? null : () => _move(index, 1),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.negative),
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeBrand(brand),
          ),
        ],
      ),
    );
  }

  Widget _catalogChip(String brand, bool selected) {
    return GestureDetector(
      onTap: () => selected ? _removeBrand(brand) : _addBrand(brand),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(brand,
                style: TextStyle(
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(selected ? Icons.remove : Icons.add,
                size: 14,
                color:
                    selected ? AppColors.primary : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _dirButton(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primaryLight : null,
        side:
            BorderSide(color: selected ? AppColors.primary : AppColors.divider),
      ),
      child: Text(label,
          style: TextStyle(
              color:
                  selected ? AppColors.primaryDark : AppColors.textSecondary)),
    );
  }
}
```

- [ ] **Step 4: Update the screen call site (keep the app compiling)**

In `frontend/lib/screens/skin_result_screen.dart`, find the `ProductFilterBar(...)` construction and change its `brands: brands,` argument to `catalog: brands,`. Leave the existing `final brands = brandsInResults(result.recommendations);` local as-is (Task 7 replaces it). No other change.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/skin_result/product_filter_bar_test.dart`
Expected: PASS (6 tests).

Run: `flutter test`
Expected: PASS (full suite — the whole app must still compile after the prop rename).

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/skin_result/product_filter_bar.dart frontend/lib/screens/skin_result_screen.dart frontend/test/skin_result/product_filter_bar_test.dart
git commit -m "feat(diag): filtre complet — catalogue marques, recherche, priorité ordonnée"
```

---

### Task 6: Frontend — ProductDetailSheet description section

**Files:**
- Modify: `frontend/lib/screens/skin_result/product_detail_sheet.dart`
- Test: `frontend/test/skin_result/product_card_test.dart`

**Interfaces:**
- Consumes: `ProductView.product.description` (Task 3).

- [ ] **Step 1: Write the failing test**

Append to `frontend/test/skin_result/product_card_test.dart` (inside `main()`):

```dart
  testWidgets('detail sheet shows product description when present',
      (tester) async {
    const v = ProductView(
      product: ProductRecommendation(
        productId: 9,
        name: 'Soin',
        reasonFr: 'Pour vous.',
        description: 'Formule apaisante sans parfum.',
        matchedConditions: [],
      ),
      matchPercent: 80,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ProductDetailSheet.show(
              context,
              view: v,
              matchedLabels: const [],
              onAdd: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.textContaining('Formule apaisante'), findsOneWidget);
  });
```

(The file already imports `ProductRecommendation`, `ProductView`, `ProductDetailSheet` from Task 4.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/product_card_test.dart`
Expected: FAIL (no `Description` section rendered).

- [ ] **Step 3: Implement**

In `frontend/lib/screens/skin_result/product_detail_sheet.dart`, in the `build` method, insert a description block immediately after the existing "Pourquoi ce produit" block (after the `Text(p.reasonFr, ...)` widget and before the trailing `SizedBox` + `Ajouter` button). Use this:

```dart
          if (p.description != null && p.description!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Description',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(p.description!,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/skin_result/product_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result/product_detail_sheet.dart frontend/test/skin_result/product_card_test.dart
git commit -m "feat(diag): description produit dans la fiche détaillée"
```

---

### Task 7: Frontend — screen catalog wiring + capture_flow fetch

**Files:**
- Modify: `frontend/lib/screens/skin_result_screen.dart`
- Modify: `frontend/lib/capture/capture_flow.dart`
- Test: `frontend/test/skin_result/skin_result_screen_test.dart`

**Interfaces:**
- Consumes: `ProductFilterBar(catalog: ...)` (Task 5); `SkinApi.fetchBrands()` (Task 4); `brandsInResults` (`skin_derivations.dart`).
- Produces: `SkinResultScreen({..., List<String> brandCatalog = const []})`.

- [ ] **Step 1: Write the failing test**

Append to `frontend/test/skin_result/skin_result_screen_test.dart` (inside `main()`):

```dart
  testWidgets('brandCatalog param feeds the filter bar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SkinResultScreen(
        result: sample(),
        onRetry: () {},
        brandCatalog: const ['Avene', 'Vichy', 'Cerave'],
      ),
    ));
    // Open the filter panel.
    await tester.tap(find.text('Filtrer et trier les produits'));
    await tester.pumpAndSettle();
    expect(find.text('Cerave'), findsOneWidget); // from the catalog, not results
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/skin_result/skin_result_screen_test.dart`
Expected: FAIL (`brandCatalog` param undefined).

- [ ] **Step 3: Implement**

In `frontend/lib/screens/skin_result_screen.dart`:
- Add the optional field + constructor param:
  ```dart
  final List<String> brandCatalog;
  ```
  and in the constructor: `this.brandCatalog = const [],` (after `this.frontPhoto`).
- In `build`, where `brands` / the `ProductFilterBar` is constructed, compute the catalog and pass it:
  ```dart
  final catalog = widget.brandCatalog.isNotEmpty
      ? widget.brandCatalog
      : brandsInResults(result.recommendations);
  ```
  (place this near the other derived locals, e.g. next to `final brands = ...`). Then change the `ProductFilterBar(...)` call: replace the `brands: brands,` argument with `catalog: catalog,`. Remove the now-unused `final brands = brandsInResults(...)` local if present.

In `frontend/lib/capture/capture_flow.dart`, in `_startAnalysis`, change the `onResult` callback of `AnalyzingScreen` so it fetches the brand catalog before navigating. The current callback is:

```dart
          onResult: (result) => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SkinResultScreen(
                result: result,
                frontPhoto: front,
                onRetry: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ),
          ),
```

Replace it with:

```dart
          onResult: (result) async {
            final catalog = await api.fetchBrands();
            if (!context.mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => SkinResultScreen(
                  result: result,
                  frontPhoto: front,
                  brandCatalog: catalog,
                  onRetry: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ),
            );
          },
```

(`api` is the `SkinApi` already created earlier in `_startAnalysis`.)

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/skin_result/skin_result_screen_test.dart`
Expected: PASS.

Run: `flutter test`
Expected: PASS (full suite).

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/skin_result_screen.dart frontend/lib/capture/capture_flow.dart frontend/test/skin_result/skin_result_screen_test.dart
git commit -m "feat(diag): câblage catalogue marques (écran + capture_flow)"
```

---

## Self-Review

**1. Spec coverage:**
- `GET /v1/skin/brands` (real, sorted, active, no null/blank) → Task 1 ✅
- `description` through recommendations → Task 2 ✅
- Model `description` → Task 3 ✅
- `fetchBrands()` → Task 4 ✅
- Filter redesign (search, catalog +/-, priority reorder/remove/clear, sort Score/Ordre) → Task 5 ✅
- Detail sheet description → Task 6 ✅
- Screen catalog wiring + capture_flow fetch + fallback to brandsInResults → Task 7 ✅
- Expiry/EAN dropped → not built ✅

**2. Placeholder scan:** No TBD/TODO; each code step has complete code; each test step has full bodies. Task 4 intentionally has no unit test (thin graceful HTTP wrapper) — analyzer-verified, exercised via the app; not a placeholder.

**3. Type consistency:** `ProductFilterBar(catalog:)` (Task 5) matches the call site in Task 7. `SkinResultScreen(brandCatalog:)` (Task 7) matches capture_flow's call. `ProductRecommendation.description` (Task 3) is consumed by Task 6's detail sheet and Task 2's backend field name (`description`). `SkinApi.fetchBrands()` (Task 4) is called in Task 7. `FilterState.copyWith(priorityBrands/useAllBrands/...)` used in Task 5 matches the existing signature. `brandsInResults` (existing) used in Task 7.
