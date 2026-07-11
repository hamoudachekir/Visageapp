# Estimation d'âge & « âge de la peau » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter au module peau l'estimation d'âge IA (Face++ Detect, repli InsightFace), la comparaison avec l'âge réel (`clients.birth_date`), le message « âge de la peau », et leur impact sur les recommandations — backend + Flutter.

**Architecture:** Nouveau fichier `backend/app/skin/age.py` (même pattern hybride que le module peau : parser pur + estimateurs + façade absorbe-tout). Colonnes ajoutées par script de migration idempotent (pattern existant). Le routeur `/v1/skin/analyze` appelle `estimate_age` sur la photo front déjà en mémoire, jamais bloquant (`age: null` au pire).

**Tech Stack:** FastAPI + SQLAlchemy synchrone, Pydantic v2, httpx (Face++ Detect), InsightFace existant (repli), pytest ; Flutter (date picker natif, modèles fromJson).

**Spec:** `docs/superpowers/specs/2026-07-11-age-estimation-skin-age-design.md`

## Global Constraints

- Chaînes visibles utilisateur et docstrings **en français**. Routes `/v1`.
- SQLAlchemy synchrone ; photos en mémoire uniquement (aucun stockage).
- `estimated_age` toujours présenté comme **estimation** (API docs, README, UI).
- L'échec de l'estimation d'âge ne casse **jamais** la réponse peau (`age: null`).
- Messages skin age exacts : delta ≤ −3 → `Votre peau paraît {abs(delta)} ans plus jeune que votre âge !` ; −2..2 → `Votre peau correspond à votre âge.` ; ≥ 3 → `Votre peau paraît {delta} ans de plus — voici des soins ciblés.` ; sans birth_date → `Votre peau paraît {estimated_age} ans (estimation).`
- Validation birth_date : âge entre **13 et 110** ans, message 422 : `Date de naissance invalide : l'âge doit être entre 13 et 110 ans.`
- Recommandations : rides retenues seulement si `score ≥ 40` OU `age ≥ 35` OU âge inconnu (seuil global 30 inchangé) ; `AGE_DELTA_BOOST = 1.5` sur `wrinkles`/`dark_spots` si `skin_age_delta ≥ 3` ; filtres `min_age`/`max_age` NULL = tout âge, ignorés si âge inconnu.
- Tests backend : `cd backend && python -m pytest tests -v`. Flutter : `cd frontend && flutter test && flutter analyze`.
- Un commit par tâche, message FR conventionnel, terminé par `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Logique pure d'âge (parser Detect, âge réel, messages)

**Files:**
- Create: `backend/app/skin/age.py` (partie pure)
- Test: `backend/tests/test_age_logic.py`, `backend/tests/test_age_estimator.py` (parser seulement)

**Interfaces:**
- Consumes: `NoFaceError` de `app/skin/analyzer.py`.
- Produces: `AgeEstimate(age: int, sexe: str | None = None)` (dataclass) ; `parse_detect(payload: dict) -> AgeEstimate` ; `real_age_from_birth_date(birth_date: date, today: date | None = None) -> int` ; `skin_age_message_fr(delta: int) -> str` ; `GENDER_FR` ; `FACEPP_DETECT_ENDPOINT_DEFAULT`.

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_age_logic.py` :

```python
"""Tests des fonctions pures : âge réel depuis la date de naissance, messages FR."""
from datetime import date

from app.skin.age import real_age_from_birth_date, skin_age_message_fr


def test_age_reel_avant_anniversaire():
    # Né le 15/08/1998, on est le 11/07/2026 -> 27 ans (anniversaire pas passé).
    assert real_age_from_birth_date(date(1998, 8, 15), today=date(2026, 7, 11)) == 27


def test_age_reel_apres_anniversaire():
    assert real_age_from_birth_date(date(1998, 6, 15), today=date(2026, 7, 11)) == 28


def test_age_reel_jour_anniversaire():
    assert real_age_from_birth_date(date(1998, 7, 11), today=date(2026, 7, 11)) == 28


def test_message_peau_plus_jeune():
    assert (
        skin_age_message_fr(-4)
        == "Votre peau paraît 4 ans plus jeune que votre âge !"
    )
    assert skin_age_message_fr(-3).startswith("Votre peau paraît 3 ans plus jeune")


def test_message_peau_conforme():
    for delta in (-2, -1, 0, 1, 2):
        assert skin_age_message_fr(delta) == "Votre peau correspond à votre âge."


def test_message_peau_plus_agee():
    assert (
        skin_age_message_fr(3)
        == "Votre peau paraît 3 ans de plus — voici des soins ciblés."
    )
    assert "5 ans de plus" in skin_age_message_fr(5)
```

`backend/tests/test_age_estimator.py` (partie parser — les estimateurs arrivent en Task 2) :

```python
"""Tests de l'estimation d'âge : parser Face++ Detect (Task 1) + moteurs (Task 2)."""
import pytest

from app.skin.age import AgeEstimate, parse_detect
from app.skin.analyzer import NoFaceError

DETECT_ONE_FACE = {
    "faces": [
        {
            "face_rectangle": {"width": 200, "height": 220, "top": 10, "left": 10},
            "attributes": {
                "age": {"value": 32},
                "gender": {"value": "Male"},
            },
        }
    ]
}

DETECT_TWO_FACES = {
    "faces": [
        {
            "face_rectangle": {"width": 80, "height": 90},
            "attributes": {"age": {"value": 60}, "gender": {"value": "Female"}},
        },
        {
            "face_rectangle": {"width": 300, "height": 320},
            "attributes": {"age": {"value": 25}, "gender": {"value": "Female"}},
        },
    ]
}


def test_parse_un_visage():
    estimate = parse_detect(DETECT_ONE_FACE)
    assert estimate == AgeEstimate(age=32, sexe="Homme")


def test_parse_plusieurs_visages_prend_le_plus_grand():
    estimate = parse_detect(DETECT_TWO_FACES)
    assert estimate.age == 25
    assert estimate.sexe == "Femme"


def test_parse_aucun_visage():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": []})
    with pytest.raises(NoFaceError):
        parse_detect({})


def test_parse_attributs_absents():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": [{"face_rectangle": {"width": 200, "height": 200}}]})
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_age_logic.py tests/test_age_estimator.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.age'`

- [ ] **Step 3: Implémenter**

`backend/app/skin/age.py` :

```python
"""Estimation d'âge & « âge de la peau ».

Partie pure (Task 1) : parser Face++ Detect, âge réel depuis la date de
naissance, messages FR. Les estimateurs (Face++ / InsightFace) et la façade
`estimate_age` arrivent en Task 2 dans ce même fichier.

`estimated_age` est une **estimation** IA — jamais présentée comme exacte.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from .analyzer import NoFaceError

FACEPP_DETECT_ENDPOINT_DEFAULT = "https://api-us.faceplusplus.com/facepp/v3/detect"

GENDER_FR = {"Male": "Homme", "Female": "Femme"}


@dataclass
class AgeEstimate:
    """Résultat d'un estimateur : âge (estimation) + sexe éventuel."""

    age: int
    sexe: str | None = None


def parse_detect(payload: dict) -> AgeEstimate:
    """Convertit la réponse Face++ Detect (v3) en AgeEstimate.

    Plusieurs visages : on prend le plus grand (la validation qualité amont
    rejette déjà le multi-visages quand le modèle CV local est chargé).
    """
    faces = payload.get("faces") or []
    if not faces:
        raise NoFaceError("aucun visage détecté (estimation d'âge).")

    def _area(face: dict) -> int:
        rect = face.get("face_rectangle") or {}
        return int(rect.get("width", 0)) * int(rect.get("height", 0))

    face = max(faces, key=_area)
    attributes = face.get("attributes") or {}
    age_value = (attributes.get("age") or {}).get("value")
    if age_value is None:
        raise NoFaceError("attributs d'âge absents (estimation d'âge).")
    gender_value = (attributes.get("gender") or {}).get("value")
    return AgeEstimate(age=int(age_value), sexe=GENDER_FR.get(gender_value))


def real_age_from_birth_date(birth_date: date, today: date | None = None) -> int:
    """Âge révolu à la date du jour (anniversaire pris en compte)."""
    today = today or date.today()
    return (
        today.year
        - birth_date.year
        - ((today.month, today.day) < (birth_date.month, birth_date.day))
    )


def skin_age_message_fr(delta: int) -> str:
    """Message marketing selon l'écart âge estimé − âge réel."""
    if delta <= -3:
        return f"Votre peau paraît {abs(delta)} ans plus jeune que votre âge !"
    if delta >= 3:
        return f"Votre peau paraît {delta} ans de plus — voici des soins ciblés."
    return "Votre peau correspond à votre âge."
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_age_logic.py tests/test_age_estimator.py -v`
Expected: 10 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/age.py backend/tests/test_age_logic.py backend/tests/test_age_estimator.py
git commit -m "feat(backend): logique pure âge — parser Detect, âge réel, messages FR"
```

---

### Task 2: Estimateurs Face++ / InsightFace + façade estimate_age

**Files:**
- Modify: `backend/app/skin/age.py` (ajouter à la fin)
- Test: `backend/tests/test_age_estimator.py` (ajouter à la fin)

**Interfaces:**
- Consumes: `parse_detect`, `AgeEstimate` (Task 1) ; `downscale_for_facepp`, `_raise_for_facepp_error` de `app/skin/facepp.py` ; `EngineUnavailableError`, `FaceppUnavailableError`, `NoFaceError`, `SkinEngineError` de `app/skin/analyzer.py` ; `vision.analyze_demographics`.
- Produces: `AgeEstimator` (ABC, `async estimate(image_bytes) -> AgeEstimate`) ; `FaceppAgeEstimator(name="facepp")` avec `_post` monkeypatchable ; `LocalAgeEstimator(name="local")` ; `async estimate_age(front_bytes: bytes, mode: str | None = None) -> tuple[AgeEstimate | None, str | None]` (résultat, nom du moteur) — **absorbe toute SkinEngineError**.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `backend/tests/test_age_estimator.py` :

```python
import httpx

from app.skin import age as age_mod
from app.skin.age import (
    FaceppAgeEstimator,
    LocalAgeEstimator,
    estimate_age,
)
from app.skin.analyzer import EngineUnavailableError, FaceppQuotaError


def _response(payload: dict, status: int = 200) -> httpx.Response:
    return httpx.Response(
        status, json=payload, request=httpx.Request("POST", "https://facepp.test")
    )


async def test_facepp_estimator_ok(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")

    async def fake_post(image_bytes):
        return _response(DETECT_ONE_FACE)

    monkeypatch.setattr(estimator, "_post", fake_post)
    estimate = await estimator.estimate(b"x")
    assert estimate.age == 32


async def test_facepp_estimator_quota(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")

    async def fake_post(image_bytes):
        return _response({"error_message": "CONCURRENCY_LIMIT_EXCEEDED"}, status=403)

    monkeypatch.setattr(estimator, "_post", fake_post)
    with pytest.raises(FaceppQuotaError):
        await estimator.estimate(b"x")


async def test_facepp_estimator_reseau_deux_tentatives(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")
    calls: list[int] = []

    async def fake_post(image_bytes):
        calls.append(1)
        raise httpx.ConnectTimeout("boom")

    monkeypatch.setattr(estimator, "_post", fake_post)
    with pytest.raises(Exception):
        await estimator.estimate(b"x")
    assert len(calls) == 2


async def test_local_estimator_ok(monkeypatch):
    monkeypatch.setattr(
        "app.skin.age.vision",
        type(
            "FakeVision",
            (),
            {
                "analyze_demographics": staticmethod(
                    lambda raw: {
                        "ok": True,
                        "demographics": {"age_estime": 41, "sexe": "Femme"},
                    }
                )
            },
        ),
    )
    estimate = await LocalAgeEstimator().estimate(b"x")
    assert estimate.age == 41
    assert estimate.sexe == "Femme"


async def test_local_estimator_modele_non_charge(monkeypatch):
    def boom(raw):
        raise RuntimeError("Modèle non chargé")

    monkeypatch.setattr(
        "app.skin.age.vision",
        type("FakeVision", (), {"analyze_demographics": staticmethod(boom)}),
    )
    with pytest.raises(EngineUnavailableError):
        await LocalAgeEstimator().estimate(b"x")


async def test_estimate_age_absorbe_les_echecs(monkeypatch):
    class FailingEstimator:
        name = "fake"

        async def estimate(self, image_bytes):
            raise FaceppQuotaError("quota")

    monkeypatch.setattr(age_mod, "_make_estimator", lambda name: FailingEstimator())
    estimate, engine = await estimate_age(b"x", mode="facepp")
    assert estimate is None and engine is None


async def test_estimate_age_auto_replie_sur_local(monkeypatch):
    class Quota:
        name = "facepp"

        async def estimate(self, image_bytes):
            raise FaceppQuotaError("quota")

    class Ok:
        name = "local"

        async def estimate(self, image_bytes):
            return AgeEstimate(age=30)

    monkeypatch.setattr(
        age_mod, "_make_estimator", lambda name: Quota() if name == "facepp" else Ok()
    )
    estimate, engine = await estimate_age(b"x", mode="auto")
    assert estimate.age == 30
    assert engine == "local"
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_age_estimator.py -v`
Expected: FAIL — `ImportError: cannot import name 'FaceppAgeEstimator'`

- [ ] **Step 3: Implémenter**

Compléter les imports en tête de `backend/app/skin/age.py` :

```python
import logging
import os
from abc import ABC, abstractmethod

import httpx

from .. import vision
from .analyzer import (
    EngineUnavailableError,
    FaceppUnavailableError,
    NoFaceError,
    SkinEngineError,
)
from .facepp import _raise_for_facepp_error, downscale_for_facepp

logger = logging.getLogger("skin.age")
```

(garder les imports existants `dataclass`, `date`, `NoFaceError` — fusionner proprement)

Ajouter à la fin du fichier :

```python
class AgeEstimator(ABC):
    """Interface commune des estimateurs d'âge (Face++ / local)."""

    name: str = "abstract"

    @abstractmethod
    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        """Estime l'âge. Lève NoFaceError ou EngineUnavailableError."""


class FaceppAgeEstimator(AgeEstimator):
    """Primaire : Face++ Detect v3 avec return_attributes=age,gender."""

    name = "facepp"

    def __init__(
        self,
        api_key: str | None = None,
        api_secret: str | None = None,
        endpoint: str | None = None,
        timeout: float = 10.0,
    ):
        self.api_key = api_key if api_key is not None else os.getenv("FACEPP_API_KEY", "")
        self.api_secret = (
            api_secret if api_secret is not None else os.getenv("FACEPP_API_SECRET", "")
        )
        self.endpoint = endpoint or os.getenv(
            "FACEPP_DETECT_ENDPOINT", FACEPP_DETECT_ENDPOINT_DEFAULT
        )
        self.timeout = timeout

    async def _post(self, image_bytes: bytes) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            return await client.post(
                self.endpoint,
                data={
                    "api_key": self.api_key,
                    "api_secret": self.api_secret,
                    "return_attributes": "age,gender",
                },
                files={"image_file": ("photo.jpg", image_bytes, "image/jpeg")},
            )

    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        if not self.api_key or not self.api_secret:
            raise FaceppUnavailableError(
                "Clés Face++ manquantes (FACEPP_API_KEY / FACEPP_API_SECRET)."
            )
        image_bytes = downscale_for_facepp(image_bytes)
        for _attempt in (1, 2):  # même politique de retry que le module peau
            try:
                response = await self._post(image_bytes)
            except httpx.TransportError:
                continue
            if response.status_code >= 500:
                continue
            try:
                payload = response.json()
            except ValueError as exc:
                raise FaceppUnavailableError(
                    "Réponse du service d'analyse illisible (corps non JSON)."
                ) from exc
            error_message = payload.get("error_message")
            if error_message:
                _raise_for_facepp_error(error_message)
            return parse_detect(payload)
        raise FaceppUnavailableError(
            "Service d'estimation d'âge injoignable (réseau ou délai, 2 tentatives)."
        )


class LocalAgeEstimator(AgeEstimator):
    """Repli : InsightFace déjà chargé (vision.analyze_demographics)."""

    name = "local"

    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        try:
            result = vision.analyze_demographics(image_bytes)
        except RuntimeError as exc:  # modèle CV non chargé
            raise EngineUnavailableError(
                "Estimation d'âge locale indisponible (modèle CV non chargé)."
            ) from exc
        except ValueError as exc:  # image illisible
            raise NoFaceError("image illisible (estimation d'âge locale).") from exc
        if not result.get("ok"):
            raise NoFaceError("aucun visage détecté (estimation d'âge locale).")
        demographics = result.get("demographics") or {}
        return AgeEstimate(
            age=int(demographics.get("age_estime", 0)),
            sexe=demographics.get("sexe"),
        )


_MODES = {"facepp": ["facepp"], "local": ["local"], "auto": ["facepp", "local"]}


def _make_estimator(name: str) -> AgeEstimator:
    if name == "facepp":
        return FaceppAgeEstimator()
    if name == "local":
        return LocalAgeEstimator()
    raise EngineUnavailableError(f"Moteur d'âge inconnu : {name}")


async def estimate_age(
    front_bytes: bytes, mode: str | None = None
) -> tuple[AgeEstimate | None, str | None]:
    """Estime l'âge sur la photo de face. N'échoue jamais : (None, None) au pire."""
    mode = mode or os.getenv("ANALYSIS_ENGINE", "facepp")
    for engine_name in _MODES.get(mode, ["facepp"]):
        try:
            estimator = _make_estimator(engine_name)
            return await estimator.estimate(front_bytes), estimator.name
        except SkinEngineError as exc:
            logger.warning(
                "Estimation d'âge (%s) échouée : %s", engine_name, exc.message_fr
            )
    return None, None
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_age_estimator.py tests/test_age_logic.py -v`
Expected: 17 PASS. Puis suite complète : `python -m pytest tests -v` — aucune régression.

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/age.py backend/tests/test_age_estimator.py
git commit -m "feat(backend): estimateurs d'âge Face++ Detect + InsightFace, façade absorbe-tout"
```

---

### Task 3: Migration + modèles (birth_date, colonnes âge, min/max_age)

**Files:**
- Modify: `backend/app/models.py`
- Create: `backend/scripts/migrate_age_columns.py`
- Test: `backend/tests/test_age_columns.py`

**Interfaces:**
- Produces: `Client.birth_date (Date, nullable)` ; `SkinAnalysis.estimated_age/real_age/skin_age_delta (Integer, nullable)` ; `ConditionProductMap.min_age/max_age (Integer, nullable)` ; script `python -m scripts.migrate_age_columns` (PostgreSQL, idempotent).

- [ ] **Step 1: Écrire le test qui échoue**

`backend/tests/test_age_columns.py` :

```python
"""Vérifie que les nouvelles colonnes existent et persistent (sqlite create_all)."""
from datetime import date

from app.models import Client, ConditionProductMap, Pharmacy, SkinAnalysis


def test_birth_date_persiste(db_session):
    pharmacy = Pharmacy(nom="P", email="p@p.tn", password_hash="x")
    db_session.add(pharmacy)
    db_session.commit()
    client = Client(
        pharmacy_id=pharmacy.id,
        prenom="A",
        nom="B",
        telephone="1",
        birth_date=date(1998, 8, 15),
    )
    db_session.add(client)
    db_session.commit()
    assert db_session.get(Client, client.id).birth_date == date(1998, 8, 15)


def test_colonnes_age_analyse(db_session):
    pharmacy = Pharmacy(nom="P", email="p2@p.tn", password_hash="x")
    db_session.add(pharmacy)
    db_session.commit()
    analysis = SkinAnalysis(
        pharmacy_id=pharmacy.id,
        skin_type="oily",
        results_json={},
        estimated_age=32,
        real_age=28,
        skin_age_delta=4,
    )
    db_session.add(analysis)
    db_session.commit()
    saved = db_session.get(SkinAnalysis, analysis.id)
    assert (saved.estimated_age, saved.real_age, saved.skin_age_delta) == (32, 28, 4)


def test_colonnes_age_mapping():
    assert hasattr(ConditionProductMap, "min_age")
    assert hasattr(ConditionProductMap, "max_age")
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_age_columns.py -v`
Expected: FAIL — `TypeError: 'birth_date' is an invalid keyword argument for Client`

- [ ] **Step 3: Implémenter les modèles**

Dans `backend/app/models.py` : ajouter `Date` à l'import sqlalchemy existant, puis :

- Dans `class Client`, après la ligne `peau_sensible = ...` :

```python
    birth_date = Column(Date, nullable=True)  # pour l'« âge de la peau »
```

- Dans `class SkinAnalysis`, après `skin_type = ...` :

```python
    estimated_age = Column(Integer, nullable=True)  # estimation IA — jamais exacte
    real_age = Column(Integer, nullable=True)
    skin_age_delta = Column(Integer, nullable=True)
```

- Dans `class ConditionProductMap`, après `priority = ...` :

```python
    min_age = Column(Integer, nullable=True)  # NULL = tout âge
    max_age = Column(Integer, nullable=True)
```

- [ ] **Step 4: Implémenter la migration**

`backend/scripts/migrate_age_columns.py` :

```python
"""Migration idempotente : colonnes âge (clients, skin_analyses, condition_product_map).

`Base.metadata.create_all` ne modifie pas les tables existantes ; ce script
ajoute les colonnes manquantes (sans risque s'il est relancé).

Usage (depuis backend/) : python -m scripts.migrate_age_columns
"""

from __future__ import annotations

from sqlalchemy import text

from app.db import engine

STATEMENTS = [
    "ALTER TABLE clients ADD COLUMN IF NOT EXISTS birth_date DATE",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS estimated_age INTEGER",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS real_age INTEGER",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS skin_age_delta INTEGER",
    "ALTER TABLE condition_product_map ADD COLUMN IF NOT EXISTS min_age INTEGER",
    "ALTER TABLE condition_product_map ADD COLUMN IF NOT EXISTS max_age INTEGER",
]


def main() -> None:
    with engine.begin() as conn:
        for stmt in STATEMENTS:
            conn.execute(text(stmt))
    print("Migration colonnes âge appliquée.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_age_columns.py -v`
Expected: 3 PASS. Suite complète : aucune régression.

- [ ] **Step 6: Commit**

```bash
git add backend/app/models.py backend/scripts/migrate_age_columns.py backend/tests/test_age_columns.py
git commit -m "feat(backend): colonnes âge — clients.birth_date, skin_analyses, condition_product_map"
```

---

### Task 4: Endpoints clients — birth_date à la création + PATCH /v1/clients/{id}

**Files:**
- Modify: `backend/app/schemas.py` (`ClientIn` + nouveau `ClientUpdate`)
- Modify: `backend/app/main.py` (création client + nouvel endpoint PATCH)
- Test: `backend/tests/test_clients_endpoint.py`

**Interfaces:**
- Consumes: `real_age_from_birth_date` (Task 1), `Client.birth_date` (Task 3), `_owned_client_or_404` existant dans `main.py`.
- Produces: `ClientIn.birth_date: date | None` (validé 13–110 ans) ; `ClientUpdate` (tous champs optionnels : prenom, nom, telephone, email, peau_sensible, birth_date) ; `PATCH /v1/clients/{client_id}` → `ClientOut` (qui expose désormais `birth_date`).

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_clients_endpoint.py` :

```python
"""Tests des endpoints clients : birth_date à la création + PATCH partiel."""
from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import auth as auth_module
from app.db import Base, get_db
from app.main import app
from app.models import Client, Pharmacy


@pytest.fixture()
def api():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)

    session = Session()
    pharmacy = Pharmacy(nom="Test", email="t@t.tn", password_hash="x")
    session.add(pharmacy)
    session.commit()
    pharmacy_id = pharmacy.id
    session.close()

    def override_db():
        s = Session()
        try:
            yield s
        finally:
            s.close()

    def override_pharmacy():
        s = Session()
        try:
            return s.get(Pharmacy, pharmacy_id)
        finally:
            s.close()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[auth_module.get_current_pharmacy] = override_pharmacy
    yield TestClient(app), Session
    app.dependency_overrides.clear()


def _payload(**extra):
    return {"prenom": "Amel", "nom": "Ben Ali", "telephone": "0612345678", **extra}


def test_creation_avec_birth_date(api):
    client, Session = api
    res = client.post("/v1/clients", json=_payload(birth_date="1998-08-15"))
    assert res.status_code == 201, res.text
    assert res.json()["birth_date"] == "1998-08-15"


def test_creation_birth_date_trop_recente(api):
    client, _ = api
    res = client.post(
        "/v1/clients", json=_payload(birth_date=str(date.today()))
    )
    assert res.status_code == 422
    assert "13 et 110 ans" in res.text


def test_creation_birth_date_trop_ancienne(api):
    client, _ = api
    res = client.post("/v1/clients", json=_payload(birth_date="1900-01-01"))
    assert res.status_code == 422


def test_patch_birth_date(api):
    client, _ = api
    created = client.post("/v1/clients", json=_payload()).json()
    res = client.patch(
        f"/v1/clients/{created['id']}", json={"birth_date": "1990-01-20"}
    )
    assert res.status_code == 200, res.text
    assert res.json()["birth_date"] == "1990-01-20"
    assert res.json()["prenom"] == "Amel"  # champs non fournis inchangés


def test_patch_client_autre_pharmacie_404(api):
    client, Session = api
    s = Session()
    autre = Pharmacy(nom="Autre", email="a@a.tn", password_hash="x")
    s.add(autre)
    s.commit()
    intrus = Client(pharmacy_id=autre.id, prenom="X", nom="Y", telephone="1")
    s.add(intrus)
    s.commit()
    intrus_id = intrus.id
    s.close()
    res = client.patch(f"/v1/clients/{intrus_id}", json={"birth_date": "1990-01-20"})
    assert res.status_code == 404


def test_patch_prenom_vide_rejete(api):
    client, _ = api
    created = client.post("/v1/clients", json=_payload()).json()
    res = client.patch(f"/v1/clients/{created['id']}", json={"prenom": "  "})
    assert res.status_code == 422
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_clients_endpoint.py -v`
Expected: FAIL — birth_date ignoré (422/champ absent) et PATCH → 405.

- [ ] **Step 3: Implémenter les schémas**

Dans `backend/app/schemas.py`, ajouter aux imports :

```python
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .skin.age import real_age_from_birth_date
```

(remplacer la ligne d'import `datetime` existante ; garder le reste)

Modifier `ClientIn` et ajouter `ClientUpdate` :

```python
def _check_birth_date(v: date | None) -> date | None:
    """Âge entre 13 et 110 ans, sinon 422 avec message FR."""
    if v is None:
        return v
    age = real_age_from_birth_date(v)
    if age < 13 or age > 110:
        raise ValueError(
            "Date de naissance invalide : l'âge doit être entre 13 et 110 ans."
        )
    return v


class ClientIn(BaseModel):
    prenom: str
    nom: str
    telephone: str
    email: str | None = None
    peau_sensible: str = "non"
    birth_date: date | None = None

    @field_validator("birth_date")
    @classmethod
    def _valide_birth_date(cls, v: date | None) -> date | None:
        return _check_birth_date(v)


class ClientUpdate(BaseModel):
    """PATCH partiel : seuls les champs fournis sont modifiés."""

    prenom: str | None = None
    nom: str | None = None
    telephone: str | None = None
    email: str | None = None
    peau_sensible: str | None = None
    birth_date: date | None = None

    @field_validator("birth_date")
    @classmethod
    def _valide_birth_date(cls, v: date | None) -> date | None:
        return _check_birth_date(v)
```

(`ClientOut(ClientIn)` existant hérite automatiquement de `birth_date` — rien d'autre à changer.)

- [ ] **Step 4: Implémenter les endpoints**

Dans `backend/app/main.py` :

1. Ajouter `ClientUpdate` à l'import depuis `.schemas`.
2. Dans `create_client`, ajouter `birth_date=payload.birth_date,` à la construction du `Client(...)`.
3. Après `create_client`, ajouter :

```python
@app.patch("/v1/clients/{client_id}", response_model=ClientOut)
def update_client(
    client_id: int,
    payload: ClientUpdate,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> Client:
    """Met à jour les champs fournis d'un client de la pharmacie courante."""
    client = _owned_client_or_404(client_id, pharmacy, db)
    data = payload.model_dump(exclude_unset=True)
    for field in ("prenom", "nom", "telephone"):
        if field in data and (data[field] is None or not str(data[field]).strip()):
            raise HTTPException(
                status_code=422, detail=f"Le champ {field} ne peut pas être vide."
            )
    for field, value in data.items():
        setattr(client, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(client)
    return client
```

- [ ] **Step 5: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_clients_endpoint.py -v`
Expected: 6 PASS. Suite complète : aucune régression.

- [ ] **Step 6: Commit**

```bash
git add backend/app/schemas.py backend/app/main.py backend/tests/test_clients_endpoint.py
git commit -m "feat(backend): birth_date client (création validée 13-110 ans) + PATCH /v1/clients/{id}"
```

---

### Task 5: Recommandations — filtre d'âge, règle anti-âge, boost delta

**Files:**
- Modify: `backend/app/skin/recommend.py`
- Test: `backend/tests/test_recommend.py` (ajouter à la fin)

**Interfaces:**
- Consumes: colonnes `min_age`/`max_age` (Task 3).
- Produces: `build_recommendations(scores, skin_type, mappings, products, age: int | None = None, skin_age_delta: int | None = None)` ; `fetch_mappings` renvoie aussi `min_age`/`max_age` ; constantes `AGE_DELTA_BOOST = 1.5`, `WRINKLES_AGE_MIN = 35`, `WRINKLES_SCORE_OVERRIDE = 40`.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin de `backend/tests/test_recommend.py` :

```python
def test_filtre_min_max_age():
    mappings = [
        _mapping("acne", 1, 10) | {"min_age": 40, "max_age": None},   # trop jeune
        _mapping("acne", 2, 10) | {"min_age": None, "max_age": 25},   # trop vieux
        _mapping("acne", 3, 10) | {"min_age": 18, "max_age": 40},     # dans la plage
        _mapping("acne", 4, 10),                                      # sans bornes
    ]
    recs = build_recommendations(SCORES, "oily", mappings, _products(4), age=30)
    assert {r.product_id for r in recs} == {3, 4}


def test_filtre_age_ignore_si_age_inconnu():
    mappings = [_mapping("acne", 1, 10) | {"min_age": 40, "max_age": 60}]
    recs = build_recommendations(SCORES, "oily", mappings, _products(1), age=None)
    assert [r.product_id for r in recs] == [1]


def test_regle_anti_age_rides():
    scores = dict(SCORES, wrinkles=35)  # 30 <= score < 40
    mappings = [_mapping("wrinkles", 1, 10)]
    products = _products(1)
    # jeune (30 ans) + score faible -> exclu
    assert build_recommendations(scores, "oily", mappings, products, age=30) == []
    # 40 ans -> inclus
    assert [r.product_id for r in build_recommendations(scores, "oily", mappings, products, age=40)] == [1]
    # score fort (45) même jeune -> inclus
    scores_forts = dict(SCORES, wrinkles=45)
    assert [r.product_id for r in build_recommendations(scores_forts, "oily", mappings, products, age=30)] == [1]
    # âge inconnu -> inclus
    assert [r.product_id for r in build_recommendations(scores, "oily", mappings, products, age=None)] == [1]


def test_boost_delta_rides_et_taches():
    scores = dict(SCORES, wrinkles=50, dark_spots=45, acne=50)
    mappings = [
        _mapping("wrinkles", 1, 10),   # 500 ; boosté (x1.5) -> 750
        _mapping("acne", 2, 14),       # 700 : devant sans boost, derrière avec
    ]
    products = _products(2)
    sans_boost = build_recommendations(scores, "oily", mappings, products, age=40)
    assert sans_boost[0].product_id == 2
    avec_boost = build_recommendations(
        scores, "oily", mappings, products, age=40, skin_age_delta=4
    )
    assert avec_boost[0].product_id == 1
```

**Attention régression** : le test existant `test_fetchers_sqlite` compare le
dict de `fetch_mappings` à l'exact — après l'ajout des clés, mettre à jour son
assertion en :

```python
    assert mappings == [
        {
            "condition_code": "wrinkles",
            "skin_type": None,
            "product_id": 1,
            "priority": 10,
            "min_age": None,
            "max_age": None,
        }
    ]
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_recommend.py -v`
Expected: nouveaux tests FAIL — `TypeError: build_recommendations() got an unexpected keyword argument 'age'`

- [ ] **Step 3: Implémenter**

Dans `backend/app/skin/recommend.py` :

1. Après `TOP_N = 6`, ajouter :

```python
# Impact de l'âge sur les recommandations (spec 2026-07-11).
AGE_DELTA_BOOST = 1.5        # skin_age_delta >= 3 -> rides & taches boostées
WRINKLES_AGE_MIN = 35        # règle anti-âge : rides seulement si âge >= 35...
WRINKLES_SCORE_OVERRIDE = 40  # ...ou score >= 40 (ou âge inconnu)
```

2. Remplacer la signature et le début de `build_recommendations` :

```python
def build_recommendations(
    scores: dict[str, int],
    skin_type: str,
    mappings: list[dict],
    products: dict[int, dict],
    age: int | None = None,
    skin_age_delta: int | None = None,
) -> list[Recommendation]:
    """Conditions >= seuil -> produits mappés -> rang (sévérité x priorité) -> top 6.

    `age` (réel sinon estimé) filtre les lignes min_age/max_age et applique la
    règle anti-âge ; `skin_age_delta` >= 3 booste rides et taches brunes.
    """
    effective = {c: s for c, s in scores.items() if s >= RECOMMEND_THRESHOLD}
    # Règle anti-âge : rides seulement si score fort OU âge >= 35 OU âge inconnu.
    if (
        "wrinkles" in effective
        and age is not None
        and age < WRINKLES_AGE_MIN
        and effective["wrinkles"] < WRINKLES_SCORE_OVERRIDE
    ):
        del effective["wrinkles"]
    effective[f"skin_type_{skin_type}"] = SKIN_TYPE_BASE_SCORE

    boosted = {"wrinkles", "dark_spots"} if (skin_age_delta or 0) >= 3 else set()
```

3. Dans la boucle des mappings, après le filtre `skin_type`, ajouter :

```python
        # Filtre d'âge par ligne : NULL = tout âge ; âge inconnu = pas de filtre.
        if age is not None:
            if mapping.get("min_age") is not None and age < mapping["min_age"]:
                continue
            if mapping.get("max_age") is not None and age > mapping["max_age"]:
                continue
```

4. Remplacer la ligne du rang par :

```python
        # priorité 0 traitée comme 1 pour ne pas annuler le rang.
        weight = effective[condition] * max(int(mapping.get("priority") or 0), 1)
        if condition in boosted:
            weight *= AGE_DELTA_BOOST
        entry["rank"] += weight
```

5. Dans `fetch_mappings`, ajouter au dict renvoyé :

```python
            "min_age": r.min_age,
            "max_age": r.max_age,
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_recommend.py -v`
Expected: 10 PASS (6 existants + 4 nouveaux). Suite complète : aucune régression.

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/recommend.py backend/tests/test_recommend.py
git commit -m "feat(backend): recommandations sensibles à l'âge — filtre, règle anti-âge, boost delta"
```

---

### Task 6: Extension de POST /v1/skin/analyze (bloc age) + README

**Files:**
- Modify: `backend/app/skin/schemas.py` (`AgeOut`, `SkinAnalyzeResponse.age`)
- Modify: `backend/app/skin/router.py`
- Modify: `backend/README.md` (section analyse de peau)
- Test: `backend/tests/test_skin_endpoint.py` (fixture + nouveaux tests)

**Interfaces:**
- Consumes: `estimate_age`, `AgeEstimate`, `real_age_from_birth_date`, `skin_age_message_fr` (Tasks 1–2) ; `build_recommendations(..., age=, skin_age_delta=)` (Task 5) ; colonnes Task 3.
- Produces: réponse enrichie `{"age": {"estimated_age", "real_age", "skin_age_delta", "message_fr"} | null}` ; colonnes `skin_analyses` persistées ; `results_json` enrichi de `age_engine`/`sexe_estime`.

- [ ] **Step 1: Adapter la fixture existante (obligatoire avant tout)**

Dans `backend/tests/test_skin_endpoint.py`, la fixture `api` doit neutraliser le
nouvel appel `estimate_age` (sinon les tests existants feraient un vrai appel
réseau Face++ si des clés sont dans `.env`). Ajouter dans la fixture, après le
monkeypatch de `run_analysis` :

```python
    async def fake_estimate(front_bytes, mode=None):
        return None, None

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)
```

- [ ] **Step 2: Écrire les tests qui échouent**

Ajouter à la fin de `backend/tests/test_skin_endpoint.py` :

```python
from datetime import date

from app.skin.age import AgeEstimate


def test_age_null_si_estimateur_echoue(api):
    client, Session = api
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 200
    assert res.json()["age"] is None
    s = Session()
    saved = s.query(SkinAnalysis).one()
    assert saved.estimated_age is None and saved.skin_age_delta is None
    s.close()


def test_bloc_age_complet_avec_birth_date(api, monkeypatch):
    client, Session = api

    async def fake_estimate(front_bytes, mode=None):
        return AgeEstimate(age=32, sexe="Homme"), "facepp"

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)

    s = Session()
    today = date.today()
    mien = Client(
        pharmacy_id=1, prenom="A", nom="B", telephone="2",
        birth_date=today.replace(year=today.year - 28),
    )
    s.add(mien)
    s.commit()
    mien_id = mien.id
    s.close()

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(mien_id)}
    )
    assert res.status_code == 200, res.text
    age = res.json()["age"]
    assert age == {
        "estimated_age": 32,
        "real_age": 28,
        "skin_age_delta": 4,
        "message_fr": "Votre peau paraît 4 ans de plus — voici des soins ciblés.",
    }
    s = Session()
    saved = s.query(SkinAnalysis).order_by(SkinAnalysis.id.desc()).first()
    assert (saved.estimated_age, saved.real_age, saved.skin_age_delta) == (32, 28, 4)
    assert saved.results_json["age_engine"] == "facepp"
    s.close()


def test_bloc_age_sans_birth_date(api, monkeypatch):
    client, _ = api

    async def fake_estimate(front_bytes, mode=None):
        return AgeEstimate(age=32, sexe=None), "local"

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)
    res = client.post("/v1/skin/analyze", files=_files())
    age = res.json()["age"]
    assert age["estimated_age"] == 32
    assert age["real_age"] is None and age["skin_age_delta"] is None
    assert age["message_fr"] == "Votre peau paraît 32 ans (estimation)."
```

- [ ] **Step 3: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py -v`
Expected: nouveaux tests FAIL — `KeyError: 'age'` (bloc absent de la réponse).

- [ ] **Step 4: Implémenter les schémas**

Dans `backend/app/skin/schemas.py`, ajouter avant `SkinAnalyzeResponse` :

```python
class AgeOut(BaseModel):
    """Bloc âge — `estimated_age` est une estimation IA, jamais exacte."""

    estimated_age: int = Field(
        description="Âge estimé par IA sur la photo de face (estimation)."
    )
    real_age: int | None = None
    skin_age_delta: int | None = None
    message_fr: str
```

Et dans `SkinAnalyzeResponse` :

```python
    age: AgeOut | None = None
```

- [ ] **Step 5: Implémenter le routeur**

Dans `backend/app/skin/router.py` :

1. Ajouter aux imports :

```python
from .age import estimate_age, real_age_from_birth_date, skin_age_message_fr
from .schemas import AgeOut, ConditionOut, RecommendationOut, SkinAnalyzeResponse
```

(remplace l'import schemas existant)

2. Garder une référence au client vérifié — remplacer le bloc d'appartenance :

```python
    client: Client | None = None
    if client_id is not None:
        client = db.get(Client, client_id)
        if client is None or client.pharmacy_id != pharmacy.id:
            raise HTTPException(status_code=404, detail="Client introuvable")
```

3. Après `scores, skin_type, zones = aggregate(run.results)`, insérer :

```python
    # Estimation d'âge sur la photo de face déjà en mémoire — jamais bloquant.
    estimate, age_engine = await estimate_age(photos["front"])
    estimated_age = estimate.age if estimate else None
    real_age = (
        real_age_from_birth_date(client.birth_date)
        if client is not None and client.birth_date is not None
        else None
    )
    skin_age_delta = (
        estimated_age - real_age
        if estimated_age is not None and real_age is not None
        else None
    )
    age_for_reco = real_age if real_age is not None else estimated_age
```

4. Passer l'âge aux recommandations :

```python
    recommendations = build_recommendations(
        scores,
        skin_type,
        mappings,
        products,
        age=age_for_reco,
        skin_age_delta=skin_age_delta,
    )
```

5. Enrichir la persistance :

```python
    analysis = SkinAnalysis(
        pharmacy_id=pharmacy.id,
        client_id=client_id,
        skin_type=skin_type,
        estimated_age=estimated_age,
        real_age=real_age,
        skin_age_delta=skin_age_delta,
        results_json={
            "scores": scores,
            "zones": zones,
            "engine": run.engine,
            "photo_status": run.photo_status,
            "age_engine": age_engine,
            "sexe_estime": estimate.sexe if estimate else None,
        },
    )
```

6. Construire le bloc `age` avant le `return` et l'ajouter à la réponse :

```python
    age_block = None
    if estimated_age is not None:
        message_fr = (
            skin_age_message_fr(skin_age_delta)
            if skin_age_delta is not None
            else f"Votre peau paraît {estimated_age} ans (estimation)."
        )
        age_block = AgeOut(
            estimated_age=estimated_age,
            real_age=real_age,
            skin_age_delta=skin_age_delta,
            message_fr=message_fr,
        )

    return SkinAnalyzeResponse(
        analysis_id=analysis.id,
        skin_type=skin_type,
        conditions=conditions,
        recommendations=recs,
        age=age_block,
        disclaimer_fr=DISCLAIMER_FR,
    )
```

- [ ] **Step 6: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py -v`
Expected: 8 PASS (5 existants + 3 nouveaux). Suite complète : aucune régression.

- [ ] **Step 7: Documenter**

Dans `backend/README.md`, section « Analyse de peau », après le paragraphe
d'introduction de l'endpoint, ajouter :

````markdown
### Âge de la peau (estimation)

La réponse contient un bloc `age` : `estimated_age` (**estimation** IA via
Face++ Detect, repli InsightFace local selon `ANALYSIS_ENGINE`), `real_age`
(calculé depuis `clients.birth_date` si l'analyse est rattachée à un client),
`skin_age_delta` et `message_fr` (« Votre peau paraît X ans… »). Si les deux
moteurs échouent, `age` vaut `null` sans casser l'analyse. La date de
naissance se renseigne à la création du client (`POST /v1/clients`, champ
`birth_date`, âge 13–110 ans) ou via `PATCH /v1/clients/{id}`.

Migration à exécuter une fois :

```bash
python -m scripts.migrate_age_columns
```

L'âge influe sur les recommandations : filtres `min_age`/`max_age` du mapping,
produits anti-rides seulement si âge ≥ 35 ou score rides ≥ 40, et boost des
produits rides/taches si la peau paraît 3 ans de plus que l'âge réel.
````

- [ ] **Step 8: Commit**

```bash
git add backend/app/skin/schemas.py backend/app/skin/router.py backend/README.md backend/tests/test_skin_endpoint.py
git commit -m "feat(backend): bloc age dans /v1/skin/analyze — estimation, delta, message FR"
```

---

### Task 7: Flutter — modèles (AgeInfo, ClientProfile.birthDate) + tests

**Files:**
- Modify: `frontend/lib/models/skin_analysis.dart`
- Modify: `frontend/lib/models/client_profile.dart`
- Test: `frontend/test/skin_analysis_test.dart` (ajouter des cas)

**Interfaces:**
- Produces: `AgeInfo{int estimatedAge, int? realAge, int? skinAgeDelta, String messageFr}` + `SkinAnalysisResult.age: AgeInfo?` ; `ClientProfile.birthDate: DateTime?` (sérialisé `birth_date` ISO `YYYY-MM-DD` dans `toJson`, parsé dans `fromJson`, préservé par `copyWith`).

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à la fin du `main()` de `frontend/test/skin_analysis_test.dart` :

```dart
  test('bloc age présent', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [],
      'age': {
        'estimated_age': 32,
        'real_age': 28,
        'skin_age_delta': 4,
        'message_fr': 'Votre peau paraît 4 ans de plus — voici des soins ciblés.',
      },
      'disclaimer_fr': 'x',
    };
    final result = SkinAnalysisResult.fromJson(json);
    expect(result.age, isNotNull);
    expect(result.age!.estimatedAge, 32);
    expect(result.age!.realAge, 28);
    expect(result.age!.skinAgeDelta, 4);
    expect(result.age!.messageFr, contains('4 ans de plus'));
  });

  test('bloc age absent ou null', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [],
      'age': null,
      'disclaimer_fr': 'x',
    };
    expect(SkinAnalysisResult.fromJson(json).age, isNull);
  });
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd frontend && flutter test test/skin_analysis_test.dart`
Expected: FAIL — `The getter 'age' isn't defined for the class 'SkinAnalysisResult'`

- [ ] **Step 3: Implémenter AgeInfo**

Dans `frontend/lib/models/skin_analysis.dart`, ajouter avant `SkinAnalysisResult` :

```dart
/// Bloc âge — `estimatedAge` est une estimation IA, jamais exacte.
class AgeInfo {
  final int estimatedAge;
  final int? realAge;
  final int? skinAgeDelta;
  final String messageFr;

  const AgeInfo({
    required this.estimatedAge,
    this.realAge,
    this.skinAgeDelta,
    required this.messageFr,
  });

  factory AgeInfo.fromJson(Map<String, dynamic> json) {
    return AgeInfo(
      estimatedAge: (json['estimated_age'] as num).toInt(),
      realAge: (json['real_age'] as num?)?.toInt(),
      skinAgeDelta: (json['skin_age_delta'] as num?)?.toInt(),
      messageFr: json['message_fr'] as String? ?? '',
    );
  }
}
```

Dans `SkinAnalysisResult` : ajouter le champ + paramètre du constructeur :

```dart
  final AgeInfo? age;
```

(constructeur : `this.age,` — optionnel) et dans `fromJson` :

```dart
      age: json['age'] == null
          ? null
          : AgeInfo.fromJson(json['age'] as Map<String, dynamic>),
```

- [ ] **Step 4: Implémenter ClientProfile.birthDate**

Remplacer `frontend/lib/models/client_profile.dart` par :

```dart
class ClientProfile {
  /// Identifiant en base. Null tant que le client n'a pas été persisté.
  final int? id;
  final String prenom;
  final String nom;
  final String telephone;
  final String? email;
  final String peauSensible;

  /// Date de naissance (optionnelle) — sert au calcul de l'« âge de la peau ».
  final DateTime? birthDate;

  const ClientProfile({
    this.id,
    required this.prenom,
    required this.nom,
    required this.telephone,
    this.email,
    required this.peauSensible,
    this.birthDate,
  });

  String get nomComplet => '$prenom $nom';

  bool get isPersisted => id != null;

  ClientProfile copyWith({int? id}) => ClientProfile(
        id: id ?? this.id,
        prenom: prenom,
        nom: nom,
        telephone: telephone,
        email: email,
        peauSensible: peauSensible,
        birthDate: birthDate,
      );

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: (json['id'] as num?)?.toInt(),
        prenom: json['prenom'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        email: json['email'] as String?,
        peauSensible: (json['peau_sensible'] as String?) ?? 'non',
        birthDate: json['birth_date'] == null
            ? null
            : DateTime.parse(json['birth_date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'prenom': prenom,
        'nom': nom,
        'telephone': telephone,
        'email': email,
        'peau_sensible': peauSensible,
        'birth_date': birthDate == null
            ? null
            : '${birthDate!.year.toString().padLeft(4, '0')}-'
                '${birthDate!.month.toString().padLeft(2, '0')}-'
                '${birthDate!.day.toString().padLeft(2, '0')}',
      };
}
```

- [ ] **Step 5: Vérifier le succès**

Run: `cd frontend && flutter test && flutter analyze lib/models`
Expected: tous les tests passent, analyze sans issue.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/models/skin_analysis.dart frontend/lib/models/client_profile.dart frontend/test/skin_analysis_test.dart
git commit -m "feat(frontend): modèles AgeInfo + birthDate client"
```

---

### Task 8: Flutter — date de naissance au formulaire nouveau client

**Files:**
- Modify: `frontend/lib/screens/new_client_screen.dart`

**Interfaces:**
- Consumes: `ClientProfile.birthDate` (Task 7) ; le dépôt existant (`ApiClientRepository.save`) envoie déjà `client.toJson()` — `birth_date` part automatiquement, rien à changer côté repository.

- [ ] **Step 1: Implémenter**

Dans `frontend/lib/screens/new_client_screen.dart` :

1. Ajouter à l'état (`_NewClientScreenState`), sous les contrôleurs existants :

```dart
  final _birthDateController = TextEditingController();
  DateTime? _birthDate;
```

2. Le disposer dans `dispose()` : `_birthDateController.dispose();`

3. Ajouter la méthode :

```dart
  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(now.year - 110, now.month, now.day),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Date de naissance du client',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateController.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }
```

4. Dans le formulaire, entre le champ Email et « Peau sensible ? », insérer :

```dart
                      const SizedBox(height: 16),
                      const LuminaFieldLabel('Date de naissance (optionnel)'),
                      TextFormField(
                        controller: _birthDateController,
                        readOnly: true,
                        onTap: _pickBirthDate,
                        decoration: LuminaUi.field(
                            hint: 'jj/mm/aaaa', icon: Icons.cake_outlined),
                      ),
```

5. Dans `_submit()`, ajouter `birthDate: _birthDate,` à la construction du `ClientProfile(...)`.

- [ ] **Step 2: Vérifier**

Run: `cd frontend && flutter analyze lib/screens/new_client_screen.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/new_client_screen.dart
git commit -m "feat(frontend): date de naissance (optionnelle) au formulaire nouveau client"
```

---

### Task 9: Flutter — carte « Âge de la peau » sur l'écran résultat

**Files:**
- Modify: `frontend/lib/screens/skin_result_screen.dart`

**Interfaces:**
- Consumes: `SkinAnalysisResult.age` / `AgeInfo` (Task 7).

- [ ] **Step 1: Implémenter**

Dans `frontend/lib/screens/skin_result_screen.dart` :

1. Dans `build`, juste avant `_buildSkinTypeCard(context),` insérer :

```dart
                  if (result.age != null) ...[
                    _buildAgeCard(context),
                    const SizedBox(height: AppSpacing.md),
                  ],
```

2. Ajouter la méthode (après `_buildSkinTypeCard`) :

```dart
  Widget _buildAgeCard(BuildContext context) {
    final age = result.age!;
    final details = StringBuffer('Estimation : ${age.estimatedAge} ans');
    if (age.realAge != null) {
      details.write(' · Âge réel : ${age.realAge} ans');
    }
    return CustomCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.cake_outlined,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Âge de la peau',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  age.messageFr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  details.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 2: Vérifier**

Run: `cd frontend && flutter analyze && flutter test`
Expected: analyze sans erreur nouvelle, tests verts.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/skin_result_screen.dart
git commit -m "feat(frontend): carte âge de la peau sur l'écran résultat"
```

---

### Task 10: Vérification de bout en bout (manuelle)

**Files:** aucun (vérification).

- [ ] **Step 1: Migration réelle + suite complète**

```bash
cd backend
python -m scripts.migrate_age_columns    # Expected: "Migration colonnes âge appliquée."
python -m pytest tests -v                # Expected: tous verts
```

- [ ] **Step 2: Smoke test API réel**

Backend lancé (`uvicorn app.main:app --port 8000`), clés Face++ dans `.env` :
login puis POST `/v1/skin/analyze` avec 4 photos de visage réelles et un
`client_id` dont le client a une `birth_date`. Expected: bloc `age` complet
(estimated/real/delta/message FR) ; vérifier en base
`SELECT estimated_age, real_age, skin_age_delta FROM skin_analyses ORDER BY id DESC LIMIT 1;`.
Refaire sans `client_id` : `real_age`/`delta` null, message « (estimation) ».

- [ ] **Step 3: Test app (téléphone)**

`adb reverse tcp:8000 tcp:8000`, `flutter run` : créer un client avec date de
naissance → capture → l'écran résultat affiche la carte « Âge de la peau » avec
le message et « Estimation : X ans · Âge réel : Y ans ».

- [ ] **Step 4: Commit final éventuel**

Si des ajustements ont été nécessaires, les committer avec un message `fix:` explicite.
