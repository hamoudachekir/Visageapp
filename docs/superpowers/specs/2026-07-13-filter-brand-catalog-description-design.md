# Full Product Filter + Real Brand Catalog + Product Description — Design Spec

**Date:** 2026-07-13
**Branch:** designe
**Scope:** Backend (FastAPI) + Frontend (Flutter). Builds on the diagnostic
redesign (2026-07-12).

## Goal

Replace the simplified product filter with the full-fidelity filter from the
reference screenshots: a **real brand catalog** (from the product DB) with a
**search box**, per-brand add, and a **"Marques sélectionnées (Ordre de
priorité)"** list supporting reorder (↑↓), remove (✕), and clear-all. Also
surface the **real product description** in the product detail sheet.

## Decisions (locked with user)

1. **Wire it to the real DB** — brand catalog and description come from real
   product data, not static/mock.
2. **Drop `Date d'expiration` sort and EAN** — those columns do not exist in
   `visage_products` and there is no data to populate them. Not built.

## Ground truth (verified)

`visage_products` columns ([models.py:124-142](../../../backend/app/models.py)):
`id, sub, brand, name, description, price, image_url, in_stock, active`.
→ `brand` and `description` are real columns. **No `expiration_date`, no
`ean`.** The recommendations API (`RecommendationOut`) currently returns
`product_id, name, brand, price, image_url, reason_fr, matched_conditions`.

## Backend changes

### 1. `GET /v1/skin/brands`
New endpoint in `backend/app/skin/router.py`, same JWT auth as `/analyze`
(`Depends(auth_module.get_current_pharmacy)`). Returns distinct, non-empty,
alphabetically-sorted brands of **active** products:

```python
class BrandsResponse(BaseModel):   # schemas.py
    brands: list[str]

@router.get("/v1/skin/brands", response_model=BrandsResponse)
def list_brands(pharmacy=Depends(...), db=Depends(get_db)) -> BrandsResponse:
    rows = (db.query(VisageProduct.brand)
              .filter(VisageProduct.active.is_(True),
                      VisageProduct.brand.isnot(None))
              .distinct().all())
    brands = sorted({r[0].strip() for r in rows if r[0] and r[0].strip()})
    return BrandsResponse(brands=brands)
```

### 2. `description` in recommendations
Thread the existing `description` column through the recommendation stack:
- `Recommendation` dataclass (`recommend.py`): add `description: str | None`.
- `fetch_products` (`recommend.py`): include `"description": r.description`.
- `build_recommendations` (`recommend.py`): set `description=product.get("description")`.
- `RecommendationOut` (`schemas.py`): add `description: str | None = None`.
- router mapping: `description=r.description`.

No DB migration (column already exists). No change to scoring/ranking.

## Frontend changes

### 3. Model
`ProductRecommendation` (`models/skin_analysis.dart`): add `final String?
description;` parsed from `json['description']`.

### 4. API client
`SkinApi.fetchBrands()` (`services/skin_api.dart`): `GET /v1/skin/brands` with
Bearer token → `List<String>`. On any error returns `[]` (graceful; caller
falls back to brands-present-in-results).

### 5. ProductFilterBar redesign
Becomes a small **StatefulWidget** (only to hold the ephemeral search text; the
actual filter still flows through `onChanged(FilterState)` — the screen owns
`FilterState`). New prop `List<String> catalog` (full brand list) replaces the
old `brands` prop.

Layout under **"Marques prioritaires"** (matching screenshots):
- **"Utiliser toutes les marques"** switch (`useAllBrands`).
- **Search box** "Rechercher des marques…" — filters the catalog chips by
  case-insensitive substring (local state, not part of `FilterState`).
- **"Marques sélectionnées (Ordre de priorité)"** — shown only when
  `priorityBrands` is non-empty: a numbered list, each row `N. BRAND` with
  **↑ / ↓** (reorder), **✕** (remove), plus a **"Tout effacer"** action that
  clears all (`priorityBrands: [], useAllBrands: true`).
- **"Ajouter plus de marques"** — a `Wrap` of the catalog (filtered by search),
  each a chip with **`＋`** (not selected) or **`－`** (selected). Tapping adds
  (append to `priorityBrands`, `useAllBrands: false`) or removes.

Sort options: **Score**, **Ordre d'affichage** (no expiration). Direction
toggle unchanged.

Reorder/remove/clear/add all emit a new `FilterState`; the existing
`productViewsForCondition` already floats `priorityBrands` in list order via a
stable sort, so priority ordering already takes effect — no derivation change
needed.

### 6. ProductDetailSheet
Add a **"Description"** section rendering `product.description` (when non-null
and non-empty), below the existing "Pourquoi ce produit" (`reasonFr`) section.

### 7. Screen wiring
- `SkinResultScreen`: new optional param `List<String> brandCatalog = const []`.
  The catalog passed to `ProductFilterBar` is
  `brandCatalog.isNotEmpty ? brandCatalog : brandsInResults(recommendations)`
  (graceful fallback for history-replay / offline). No network in the screen —
  stays testable.
- `capture_flow.dart`: in the `onResult` callback, fetch brands via
  `SkinApi(token: …).fetchBrands()` (wrapped in try/catch → `[]`) and pass them
  as `brandCatalog` to `SkinResultScreen`. This is the composition root that
  already holds the JWT.

## Data flow

```
capture_flow (has token)
  → analyze() → result
  → fetchBrands() → catalog (or [] on error)
  → SkinResultScreen(result, brandCatalog: catalog)
       → ProductFilterBar(catalog: catalog.isNotEmpty ? catalog
                                   : brandsInResults(result.recommendations))
       → user adds/reorders brands → FilterState.priorityBrands
       → productViewsForCondition floats priorityBrands (existing stable sort)
```

## Out of scope

`Date d'expiration` sort, EAN (no data). Product admin/data entry. Cart/order.
Routine engine. No changes to scoring, age logic, or the analyze pipeline.

## Testing

- **Backend:** `GET /v1/skin/brands` returns sorted distinct active brands
  (extend the `api` fixture in `test_skin_endpoint.py`); `description` appears
  in `recommendations` (extend `test_recommend.py` / `test_analyse_ok`).
- **Frontend:** `ProductRecommendation` parses `description`; `ProductFilterBar`
  — search filters chips, add appends to `priorityBrands` + sets
  `useAllBrands=false`, remove/clear/reorder emit correct `FilterState`;
  `ProductDetailSheet` shows description when present, hides when null.
