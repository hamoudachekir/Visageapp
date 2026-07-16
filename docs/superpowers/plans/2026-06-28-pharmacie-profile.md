# Profil pharmacie — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pharmacist fill, edit, and persist their profile (name, phone, address, city, description) and upload a logo, with a redesigned Lumina profile tab.

**Architecture:** Add nullable columns to the existing `Pharmacy` table (logo stored as bytes in the DB), expose JWT-scoped `PATCH /v1/pharmacy` and `/v1/pharmacy/logo` endpoints, and on the Flutter side add a `PharmacyApi` + Riverpod `pharmacyProfileProvider` feeding a redesigned `_ProfilTab` and a new edit screen.

**Tech Stack:** FastAPI + SQLAlchemy + PostgreSQL (backend), Flutter + Riverpod + http + image_picker (frontend).

## Global Constraints

- Backend run from `backend/` with `SKIP_VISION=1` already set in `.env`; test account `test@lumina.com` / `lumina123`.
- All new endpoints are JWT-scoped via `auth_module.get_current_pharmacy` — the tenant identity always comes from the token, never the request body.
- Logo upload: `Content-Type` in {`image/jpeg`, `image/jpg`, `image/png`, `image/webp`}, size ≤ 2 MB.
- Frontend bar: `flutter analyze` must stay clean (0 issues in `lib/`).
- UI copy is French; visual language is Lumina (`LuminaUi`, teal `#0C7C84`, Fraunces/Inter). No em-dashes in visible copy.
- The app uses `Base.metadata.create_all` which does NOT add columns to existing tables — schema changes ship as an idempotent migration script.
- DB is PostgreSQL (`ADD COLUMN IF NOT EXISTS` / `BYTEA` are Postgres-specific, which is fine).
- No pytest in this project; backend tasks are verified with `curl` + expected HTTP output, frontend with `flutter analyze`.

---

## File Structure

**Backend**
- `backend/app/models.py` — add 7 columns to `Pharmacy`.
- `backend/app/schemas.py` — extend `PharmacyOut`, add `PharmacyUpdate`, add `PharmacyOut.from_pharmacy`.
- `backend/app/main.py` — switch `login`/`me` to the helper; add `PATCH /v1/pharmacy` + 3 logo endpoints.
- `backend/scripts/migrate_pharmacy_profile.py` — idempotent `ALTER TABLE` migration (new).

**Frontend**
- `frontend/pubspec.yaml` — add `image_picker`, `http_parser`.
- `frontend/lib/models/pharmacy_profile.dart` — profile model (new).
- `frontend/lib/services/pharmacy_api.dart` — profile/logo HTTP client (new).
- `frontend/lib/data/auth_repository.dart` + `frontend/lib/providers/auth_provider.dart` — `updatePharmacyNom`.
- `frontend/lib/providers/pharmacy_profile_provider.dart` — Riverpod AsyncNotifier (new).
- `frontend/lib/screens/pharmacy_profile_edit_screen.dart` — edit form (new).
- `frontend/lib/screens/home_screen.dart` — rewrite `_ProfilTab`.

---

## Task 1: Backend — Pharmacy columns, migration, extended schemas

**Files:**
- Modify: `backend/app/models.py`
- Modify: `backend/app/schemas.py`
- Create: `backend/scripts/migrate_pharmacy_profile.py`

**Interfaces:**
- Produces: `Pharmacy.{telephone, adresse, ville, description, logo_bytes, logo_mime, updated_at}` columns; `PharmacyUpdate` schema; `PharmacyOut` with fields `id, nom, email, telephone, adresse, ville, description, has_logo, updated_at` and classmethod `PharmacyOut.from_pharmacy(pharmacy) -> PharmacyOut`.

- [ ] **Step 1: Add columns to the `Pharmacy` model**

In `backend/app/models.py`, update the imports line and the `Pharmacy` class:

```python
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    func,
)
```

Add these columns inside `class Pharmacy` (after `password_hash`):

```python
    telephone = Column(String, nullable=True)
    adresse = Column(String, nullable=True)
    ville = Column(String, nullable=True)
    description = Column(String, nullable=True)
    logo_bytes = Column(LargeBinary, nullable=True)
    logo_mime = Column(String, nullable=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
```

- [ ] **Step 2: Extend `PharmacyOut` and add `PharmacyUpdate` in schemas**

In `backend/app/schemas.py`, replace the `PharmacyOut` class with:

```python
class PharmacyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nom: str
    email: str
    telephone: str | None = None
    adresse: str | None = None
    ville: str | None = None
    description: str | None = None
    has_logo: bool = False
    updated_at: datetime | None = None

    @classmethod
    def from_pharmacy(cls, pharmacy) -> "PharmacyOut":
        return cls(
            id=pharmacy.id,
            nom=pharmacy.nom,
            email=pharmacy.email,
            telephone=pharmacy.telephone,
            adresse=pharmacy.adresse,
            ville=pharmacy.ville,
            description=pharmacy.description,
            has_logo=pharmacy.logo_bytes is not None,
            updated_at=pharmacy.updated_at,
        )


class PharmacyUpdate(BaseModel):
    nom: str | None = None
    telephone: str | None = None
    adresse: str | None = None
    ville: str | None = None
    description: str | None = None
```

(`datetime` is already imported at the top of `schemas.py`.)

- [ ] **Step 3: Create the migration script**

Create `backend/scripts/migrate_pharmacy_profile.py`:

```python
"""Migration idempotente : ajoute les colonnes de profil à `pharmacies`.

`Base.metadata.create_all` ne modifie pas les tables existantes ; ce script
ajoute les colonnes manquantes (sans risque s'il est relancé).

Usage (depuis backend/) : python -m scripts.migrate_pharmacy_profile
"""

from __future__ import annotations

from sqlalchemy import text

from app.db import engine

STATEMENTS = [
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS telephone VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS adresse VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS ville VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS description VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS logo_bytes BYTEA",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS logo_mime VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ",
]


def main() -> None:
    with engine.begin() as conn:
        for stmt in STATEMENTS:
            conn.execute(text(stmt))
    print("Migration profil pharmacie appliquée.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the migration**

Run (from `backend/`):
```bash
python -m scripts.migrate_pharmacy_profile
```
Expected: `Migration profil pharmacie appliquée.` (and re-running prints the same line with no error — idempotent).

- [ ] **Step 5: Verify columns exist**

Run (from `backend/`):
```bash
python -c "from sqlalchemy import text; from app.db import engine; \
print(sorted(r[0] for r in engine.connect().execute(text(\"select column_name from information_schema.columns where table_name='pharmacies'\"))))"
```
Expected: list includes `adresse, description, logo_bytes, logo_mime, telephone, updated_at, ville`.

- [ ] **Step 6: Commit**

```bash
git add backend/app/models.py backend/app/schemas.py backend/scripts/migrate_pharmacy_profile.py
git commit -m "feat(backend): pharmacy profile columns + migration + schemas"
```

---

## Task 2: Backend — PATCH /v1/pharmacy + extend login/me

**Files:**
- Modify: `backend/app/main.py`

**Interfaces:**
- Consumes: `PharmacyOut.from_pharmacy`, `PharmacyUpdate` (Task 1).
- Produces: `PATCH /v1/pharmacy` returning extended `PharmacyOut`; `login` and `me` now return the extended payload.

- [ ] **Step 1: Import the new schema and switch login/me to the helper**

In `backend/app/main.py`, add `PharmacyUpdate` to the `from .schemas import (...)` block.

Replace the return line in `login` (`return LoginResponse(...)`):
```python
    return LoginResponse(
        token=token, pharmacy=PharmacyOut.from_pharmacy(pharmacy)
    )
```

Replace the body of `me`:
```python
    return PharmacyOut.from_pharmacy(pharmacy)
```

- [ ] **Step 2: Add the PATCH endpoint**

In `backend/app/main.py`, after the `me` endpoint, add:

```python
@app.patch("/v1/pharmacy", response_model=PharmacyOut)
def update_pharmacy(
    payload: PharmacyUpdate,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Met à jour les champs de profil fournis (les autres restent inchangés)."""
    data = payload.model_dump(exclude_unset=True)
    if "nom" in data and (data["nom"] is None or not data["nom"].strip()):
        raise HTTPException(status_code=422, detail="Le nom ne peut pas être vide.")
    for field, value in data.items():
        setattr(pharmacy, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)
```

- [ ] **Step 3: Start the backend**

Run (from `backend/`, leave running in another shell):
```bash
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- [ ] **Step 4: Verify login returns the new fields**

Run:
```bash
curl -s -X POST http://127.0.0.1:8000/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@lumina.com","password":"lumina123"}'
```
Expected: JSON whose `pharmacy` object now contains `telephone`, `adresse`, `ville`, `description` (all `null`), `has_logo: false`, and `updated_at`.

- [ ] **Step 5: Verify PATCH updates fields**

Run:
```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/v1/auth/login -H "Content-Type: application/json" -d '{"email":"test@lumina.com","password":"lumina123"}' | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s -X PATCH http://127.0.0.1:8000/v1/pharmacy \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"telephone":"71 123 456","ville":"Tunis","description":"Votre parapharmacie de confiance"}'
```
Expected: JSON with `telephone":"71 123 456"`, `ville":"Tunis"`, `description":"Votre parapharmacie de confiance"`, and a non-null `updated_at`.

- [ ] **Step 6: Commit**

```bash
git add backend/app/main.py
git commit -m "feat(backend): PATCH /v1/pharmacy + extended login/me payload"
```

---

## Task 3: Backend — logo upload / serve / delete

**Files:**
- Modify: `backend/app/main.py`

**Interfaces:**
- Consumes: `MAX_IMAGE_BYTES`, `ALLOWED_CONTENT_TYPES` (already in `main.py`), `PharmacyOut.from_pharmacy`.
- Produces: `POST /v1/pharmacy/logo` (multipart, returns `PharmacyOut`), `GET /v1/pharmacy/logo` (image bytes), `DELETE /v1/pharmacy/logo` (returns `PharmacyOut`).

- [ ] **Step 1: Add `Response` to the FastAPI imports**

In `backend/app/main.py`, change the FastAPI import line to:
```python
from fastapi import Depends, FastAPI, File, HTTPException, Response, UploadFile
```

- [ ] **Step 2: Add the three logo endpoints**

After the `update_pharmacy` endpoint, add:

```python
MAX_LOGO_BYTES = 2 * 1024 * 1024  # 2 Mo — garde-fou logo


@app.post("/v1/pharmacy/logo", response_model=PharmacyOut)
async def upload_logo(
    image: UploadFile = File(...),
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Téléverse / remplace le logo (stocké en octets dans la base)."""
    if image.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"Type non supporté : {image.content_type}.",
        )
    raw = await image.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Image vide.")
    if len(raw) > MAX_LOGO_BYTES:
        raise HTTPException(status_code=413, detail="Logo trop volumineux (max 2 Mo).")
    pharmacy.logo_bytes = raw
    pharmacy.logo_mime = image.content_type
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)


@app.get("/v1/pharmacy/logo")
def get_logo(
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
) -> Response:
    """Renvoie les octets du logo de la pharmacie courante (404 si absent)."""
    if pharmacy.logo_bytes is None:
        raise HTTPException(status_code=404, detail="Aucun logo.")
    return Response(
        content=pharmacy.logo_bytes,
        media_type=pharmacy.logo_mime or "image/png",
    )


@app.delete("/v1/pharmacy/logo", response_model=PharmacyOut)
def delete_logo(
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Supprime le logo."""
    pharmacy.logo_bytes = None
    pharmacy.logo_mime = None
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)
```

- [ ] **Step 3: Verify upload + serve + delete (backend running)**

Run (creates a tiny 1x1 PNG, uploads it, fetches it back, deletes it):
```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/v1/auth/login -H "Content-Type: application/json" -d '{"email":"test@lumina.com","password":"lumina123"}' | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
python -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC'))" > /tmp/logo.png
echo "--- upload ---"; curl -s -X POST http://127.0.0.1:8000/v1/pharmacy/logo -H "Authorization: Bearer $TOKEN" -F "image=@/tmp/logo.png;type=image/png"
echo; echo "--- serve status ---"; curl -s -o /tmp/out.png -w "%{http_code} %{content_type}\n" http://127.0.0.1:8000/v1/pharmacy/logo -H "Authorization: Bearer $TOKEN"
echo "--- delete ---"; curl -s -X DELETE http://127.0.0.1:8000/v1/pharmacy/logo -H "Authorization: Bearer $TOKEN"
```
Expected: upload returns JSON with `"has_logo":true`; serve prints `200 image/png`; delete returns JSON with `"has_logo":false`.

- [ ] **Step 4: Commit**

```bash
git add backend/app/main.py
git commit -m "feat(backend): pharmacy logo upload/serve/delete (DB bytes)"
```

---

## Task 4: Frontend — deps, PharmacyProfile model, PharmacyApi

**Files:**
- Modify: `frontend/pubspec.yaml`
- Create: `frontend/lib/models/pharmacy_profile.dart`
- Create: `frontend/lib/services/pharmacy_api.dart`

**Interfaces:**
- Produces:
  - `PharmacyProfile{ id, nom, email, telephone?, adresse?, ville?, description?, hasLogo, updatedAt? }` with `PharmacyProfile.fromJson(Map)`.
  - `PharmacyApi({ String? token })` with:
    - `Future<PharmacyProfile> getProfile()`
    - `Future<PharmacyProfile> updateProfile({String? nom, telephone, adresse, ville, description})`
    - `Future<PharmacyProfile> uploadLogo(Uint8List bytes, String filename, String mime)`
    - `Future<PharmacyProfile> deleteLogo()`
  - `PharmacyApiException(String message)`.

- [ ] **Step 1: Add dependencies**

In `frontend/pubspec.yaml`, under `dependencies:` (after `flutter_secure_storage`), add:
```yaml
  image_picker: ^1.1.2
  http_parser: ^4.0.2
```

Run (from `frontend/`):
```bash
flutter pub get
```
Expected: resolves with no error.

- [ ] **Step 2: Create the `PharmacyProfile` model**

Create `frontend/lib/models/pharmacy_profile.dart`:

```dart
/// Profil d'une pharmacie (renvoyé par /v1/auth/me, PATCH /v1/pharmacy, etc.).
class PharmacyProfile {
  final int id;
  final String nom;
  final String email;
  final String? telephone;
  final String? adresse;
  final String? ville;
  final String? description;
  final bool hasLogo;
  final String? updatedAt;

  const PharmacyProfile({
    required this.id,
    required this.nom,
    required this.email,
    this.telephone,
    this.adresse,
    this.ville,
    this.description,
    this.hasLogo = false,
    this.updatedAt,
  });

  factory PharmacyProfile.fromJson(Map<String, dynamic> json) {
    return PharmacyProfile(
      id: (json['id'] as num).toInt(),
      nom: json['nom'] as String? ?? 'Pharmacie',
      email: json['email'] as String? ?? '',
      telephone: json['telephone'] as String?,
      adresse: json['adresse'] as String?,
      ville: json['ville'] as String?,
      description: json['description'] as String?,
      hasLogo: json['has_logo'] as bool? ?? false,
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// Jeton de cache pour l'URL du logo (change à chaque mise à jour).
  String get logoCacheKey => updatedAt ?? '0';
}
```

- [ ] **Step 3: Create the `PharmacyApi` service**

Create `frontend/lib/services/pharmacy_api.dart`:

```dart
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

  PharmacyProfile _parse(http.Response res) =>
      PharmacyProfile.fromJson(
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
```

- [ ] **Step 4: Analyze**

Run (from `frontend/`):
```bash
flutter analyze lib/models/pharmacy_profile.dart lib/services/pharmacy_api.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock frontend/lib/models/pharmacy_profile.dart frontend/lib/services/pharmacy_api.dart
git commit -m "feat(frontend): pharmacy profile model + API client + deps"
```

---

## Task 5: Frontend — session nom sync + pharmacyProfileProvider

**Files:**
- Modify: `frontend/lib/data/auth_repository.dart`
- Modify: `frontend/lib/providers/auth_provider.dart`
- Create: `frontend/lib/providers/pharmacy_profile_provider.dart`

**Interfaces:**
- Consumes: `PharmacyApi`, `PharmacyProfile` (Task 4); `authProvider`, `AuthSession` (existing).
- Produces:
  - `AuthNotifier.updatePharmacyNom(String nom)`.
  - `pharmacyProfileProvider` (`AsyncNotifierProvider<PharmacyProfileNotifier, PharmacyProfile>`) with `update({...})`, `uploadLogo(Uint8List, String filename, String mime)`, `deleteLogo()`, `refresh()`.

- [ ] **Step 1: Add `updatePharmacyNom` to the repository**

In `frontend/lib/data/auth_repository.dart`, add this method inside `AuthRepository` (after `logout`):

```dart
  /// Réécrit le nom de pharmacie stocké (après édition du profil).
  Future<void> updatePharmacyNom(String nom) async {
    await _storage.write(key: _kPharmNom, value: nom);
  }
```

- [ ] **Step 2: Add `updatePharmacyNom` to the notifier**

In `frontend/lib/providers/auth_provider.dart`, add this method inside `AuthNotifier` (after `logout`):

```dart
  /// Met à jour le nom de pharmacie en session (badge Home) + stockage.
  Future<void> updatePharmacyNom(String nom) async {
    final s = state.session;
    if (s == null) return;
    await _repo.updatePharmacyNom(nom);
    state = AuthState(
      session: AuthSession(
        token: s.token,
        pharmacyId: s.pharmacyId,
        pharmacyNom: nom,
      ),
    );
  }
```

- [ ] **Step 3: Create the profile provider**

Create `frontend/lib/providers/pharmacy_profile_provider.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pharmacy_profile.dart';
import '../services/pharmacy_api.dart';
import 'auth_provider.dart';

/// Profil pharmacie courant (chargé depuis le backend), avec édition & logo.
class PharmacyProfileNotifier extends AsyncNotifier<PharmacyProfile> {
  PharmacyApi get _api =>
      PharmacyApi(token: ref.read(authProvider).session?.token);

  @override
  Future<PharmacyProfile> build() => _api.getProfile();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_api.getProfile);
  }

  Future<void> update({
    String? nom,
    String? telephone,
    String? adresse,
    String? ville,
    String? description,
  }) async {
    final updated = await _api.updateProfile(
      nom: nom,
      telephone: telephone,
      adresse: adresse,
      ville: ville,
      description: description,
    );
    state = AsyncData(updated);
    await ref.read(authProvider.notifier).updatePharmacyNom(updated.nom);
  }

  Future<void> uploadLogo(
      Uint8List bytes, String filename, String mime) async {
    final updated = await _api.uploadLogo(bytes, filename, mime);
    state = AsyncData(updated);
  }

  Future<void> deleteLogo() async {
    final updated = await _api.deleteLogo();
    state = AsyncData(updated);
  }
}

final pharmacyProfileProvider =
    AsyncNotifierProvider<PharmacyProfileNotifier, PharmacyProfile>(
  PharmacyProfileNotifier.new,
);
```

- [ ] **Step 4: Analyze**

Run (from `frontend/`):
```bash
flutter analyze lib/data/auth_repository.dart lib/providers/auth_provider.dart lib/providers/pharmacy_profile_provider.dart
```
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/data/auth_repository.dart frontend/lib/providers/auth_provider.dart frontend/lib/providers/pharmacy_profile_provider.dart
git commit -m "feat(frontend): pharmacy profile provider + session nom sync"
```

---

## Task 6: Frontend — edit screen

**Files:**
- Create: `frontend/lib/screens/pharmacy_profile_edit_screen.dart`

**Interfaces:**
- Consumes: `pharmacyProfileProvider`, `PharmacyProfile` (Tasks 4-5), `LuminaUi`/`LuminaHeader`/`LuminaFieldLabel`/`LuminaGradientButton` (existing `widgets/lumina_ui.dart`), `PharmacyApiException`.
- Produces: `PharmacyProfileEditScreen(profile: PharmacyProfile)` widget.

- [ ] **Step 1: Create the edit screen**

Create `frontend/lib/screens/pharmacy_profile_edit_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pharmacy_profile.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../services/pharmacy_api.dart';
import '../widgets/lumina_ui.dart';

/// Formulaire d'édition du profil pharmacie (nom, téléphone, adresse, ville,
/// description). L'email reste en lecture seule (identifiant de connexion).
class PharmacyProfileEditScreen extends ConsumerStatefulWidget {
  final PharmacyProfile profile;

  const PharmacyProfileEditScreen({super.key, required this.profile});

  @override
  ConsumerState<PharmacyProfileEditScreen> createState() =>
      _PharmacyProfileEditScreenState();
}

class _PharmacyProfileEditScreenState
    extends ConsumerState<PharmacyProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _telephone;
  late final TextEditingController _adresse;
  late final TextEditingController _ville;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nom = TextEditingController(text: p.nom);
    _telephone = TextEditingController(text: p.telephone ?? '');
    _adresse = TextEditingController(text: p.adresse ?? '');
    _ville = TextEditingController(text: p.ville ?? '');
    _description = TextEditingController(text: p.description ?? '');
  }

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _adresse.dispose();
    _ville.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(pharmacyProfileProvider.notifier).update(
            nom: _nom.text.trim(),
            telephone: _telephone.text.trim(),
            adresse: _adresse.text.trim(),
            ville: _ville.text.trim(),
            description: _description.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } on PharmacyApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminaUi.bg,
      body: Column(
        children: [
          LuminaHeader(
            title: 'Modifier le profil',
            subtitle: 'Informations de votre pharmacie',
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Form(
                key: _formKey,
                child: LuminaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LuminaFieldLabel('Nom de la pharmacie'),
                      TextFormField(
                        controller: _nom,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Ex. Pharmacie du Centre',
                            icon: Icons.local_pharmacy_outlined),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Téléphone'),
                      TextFormField(
                        controller: _telephone,
                        keyboardType: TextInputType.phone,
                        decoration: LuminaUi.field(
                            hint: 'Ex. 71 123 456',
                            icon: Icons.phone_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Adresse'),
                      TextFormField(
                        controller: _adresse,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: LuminaUi.field(
                            hint: 'Rue, numéro',
                            icon: Icons.place_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Ville'),
                      TextFormField(
                        controller: _ville,
                        textCapitalization: TextCapitalization.words,
                        decoration: LuminaUi.field(
                            hint: 'Ex. Tunis',
                            icon: Icons.location_city_outlined),
                      ),
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Description'),
                      TextFormField(
                        controller: _description,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: LuminaUi.field(
                            hint: 'Votre parapharmacie de confiance',
                            icon: Icons.notes_outlined),
                      ),
                      const SizedBox(height: 24),
                      LuminaGradientButton(
                        label: 'Enregistrer',
                        icon: Icons.check,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run (from `frontend/`):
```bash
flutter analyze lib/screens/pharmacy_profile_edit_screen.dart
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/pharmacy_profile_edit_screen.dart
git commit -m "feat(frontend): pharmacy profile edit screen"
```

---

## Task 7: Frontend — redesign `_ProfilTab` (logo, info, edit, picker)

**Files:**
- Modify: `frontend/lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `pharmacyProfileProvider`, `PharmacyProfile`, `PharmacyProfileEditScreen`, `pharmacy_api` (`PharmacyApiException`), `image_picker`, `ApiConfig`, `authProvider`, `LuminaUi`/`LuminaCard`/`LuminaHeader`.
- Produces: rewritten `_ProfilTab` (same constructor `_ProfilTab({required VoidCallback onLogout})`).

- [ ] **Step 1: Add imports**

In `frontend/lib/screens/home_screen.dart`, add to the import block:

```dart
import 'package:image_picker/image_picker.dart';

import '../models/pharmacy_profile.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../services/api_config.dart';
import '../services/pharmacy_api.dart';
import 'pharmacy_profile_edit_screen.dart';
```

- [ ] **Step 2: Replace the `_ProfilTab` class**

Replace the entire `class _ProfilTab extends ConsumerWidget { ... }` (from `class _ProfilTab` to its closing brace) with:

```dart
class _ProfilTab extends ConsumerWidget {
  final VoidCallback onLogout;

  const _ProfilTab({required this.onLogout});

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime =
        picked.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    try {
      await ref
          .read(pharmacyProfileProvider.notifier)
          .uploadLogo(bytes, picked.name, mime);
    } on PharmacyApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pharmacyProfileProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Column(
        children: [
          const LuminaHeader(title: 'Profil', subtitle: 'Votre pharmacie'),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ProfilError(
                message: e.toString(),
                onRetry: () =>
                    ref.read(pharmacyProfileProvider.notifier).refresh(),
              ),
              data: (profile) => _ProfilContent(
                profile: profile,
                token: ref.watch(authProvider).session?.token,
                onEditProfile: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PharmacyProfileEditScreen(profile: profile),
                  ),
                ),
                onEditLogo: () => _pickAndUpload(context, ref),
                onLogout: onLogout,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilContent extends StatelessWidget {
  final PharmacyProfile profile;
  final String? token;
  final VoidCallback onEditProfile;
  final VoidCallback onEditLogo;
  final VoidCallback onLogout;

  const _ProfilContent({
    required this.profile,
    required this.token,
    required this.onEditProfile,
    required this.onEditLogo,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          LuminaCard(
            child: Column(
              children: [
                _LogoAvatar(
                  profile: profile,
                  token: token,
                  onTap: onEditLogo,
                ),
                const SizedBox(height: 14),
                Text(
                  profile.nom,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LuminaUi.navy,
                  ),
                ),
                if (profile.description != null &&
                    profile.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.description!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: LuminaUi.muted),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  profile.email,
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: LuminaUi.label),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LuminaCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Téléphone',
                  value: profile.telephone,
                ),
                const Divider(height: 1, color: LuminaUi.hairline),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Adresse',
                  value: profile.adresse,
                ),
                const Divider(height: 1, color: LuminaUi.hairline),
                _InfoRow(
                  icon: Icons.location_city_outlined,
                  label: 'Ville',
                  value: profile.ville,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: LuminaGradientButton(
              label: 'Modifier le profil',
              icon: Icons.edit_outlined,
              onPressed: onEditProfile,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Se déconnecter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.negative,
                side: const BorderSide(color: Color(0xFFE7CFCF)),
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.inter(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoAvatar extends StatelessWidget {
  final PharmacyProfile profile;
  final String? token;
  final VoidCallback onTap;

  const _LogoAvatar({
    required this.profile,
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initials = profile.nom.trim().isEmpty
        ? 'P'
        : profile.nom.trim()[0].toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              gradient: LuminaUi.gradient,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: profile.hasLogo && token != null
                ? Image.network(
                    '${ApiConfig.baseUrl}/v1/pharmacy/logo?v=${profile.logoCacheKey}',
                    headers: {'Authorization': 'Bearer $token'},
                    fit: BoxFit.cover,
                    width: 84,
                    height: 84,
                    errorBuilder: (_, __, ___) => Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Text(
                    initials,
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: LuminaUi.hairline),
              ),
              child: const Icon(Icons.photo_camera,
                  size: 15, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _InfoRow({required this.icon, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final filled = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 13.5, color: LuminaUi.muted),
          ),
          const Spacer(),
          Text(
            filled ? value! : 'Ajouter',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: filled ? LuminaUi.navy : LuminaUi.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfilError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 44, color: AppColors.negative),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13.5, color: LuminaUi.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze the whole lib**

Run (from `frontend/`):
```bash
flutter analyze
```
Expected: 0 issues under `lib/` (only the pre-existing `test/widget_test.dart` errors may remain).

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/home_screen.dart
git commit -m "feat(frontend): redesigned profile tab with logo + edit + info rows"
```

---

## Task 8: End-to-end manual verification

**Files:** none (verification only).

- [ ] **Step 1: Ensure migration applied + backend running**

From `backend/`: `python -m scripts.migrate_pharmacy_profile` then start uvicorn (or use `./run-dev.ps1`).

- [ ] **Step 2: Run the app on the tablet and walk the flow**

From repo root: `./run-dev.ps1`. Then:
1. Log in (`test@lumina.com` / `lumina123`).
2. Open the **Profil** tab → it loads the profile (name, email, empty info rows showing "Ajouter").
3. Tap **Modifier le profil** → fill phone, address, city, description, change the name → **Enregistrer**. Confirm the rows now show the values and the **Home badge name updated**.
4. Tap the **logo avatar** → pick an image → confirm it appears in the avatar.
5. **Kill and relaunch the app** → Profil tab still shows the saved fields and logo (persistence confirmed).

- [ ] **Step 3: Final analyze**

Run (from `frontend/`): `flutter analyze`
Expected: 0 issues in `lib/`.

---

## Self-Review

**Spec coverage:**
- New Pharmacy columns + migration → Task 1. ✔
- Extended `PharmacyOut` + `PharmacyUpdate` + `from_pharmacy` → Task 1; used in Tasks 2-3. ✔
- `PATCH /v1/pharmacy`, login/me extended → Task 2. ✔
- Logo upload/serve/delete (DB bytes, ≤2 MB, allowed types) → Task 3. ✔
- `image_picker` (+ `http_parser`) → Task 4. ✔
- `PharmacyProfile` model + `PharmacyApi` (getProfile/update/uploadLogo/deleteLogo) → Task 4. ✔
- `pharmacyProfileProvider` + session nom sync → Task 5. ✔
- Edit screen (Lumina fields, email read-only) → Task 6. ✔
- Redesigned `_ProfilTab` (logo avatar + camera badge, info rows with "Ajouter", modify button, logout) → Task 7. ✔
- Logo via `Image.network` with auth header + `?v=` cache-bust → Task 7. ✔
- Error/empty states (snackbar, retry, "Ajouter", monogram fallback) → Tasks 6-7. ✔
- Persistence + name-badge sync verified → Task 8. ✔

**Type consistency:** `PharmacyProfile.fromJson` keys match `PharmacyOut` JSON (`has_logo`, `updated_at`). `uploadLogo(Uint8List, String filename, String mime)` signature identical in `PharmacyApi`, provider, and call site. `updatePharmacyNom` defined (repo + notifier) before use. `PharmacyOut.from_pharmacy` defined in Task 1, used in Tasks 2-3.

**Placeholder scan:** No TBD/TODO; every code step shows full code; verification steps give exact commands + expected output.
