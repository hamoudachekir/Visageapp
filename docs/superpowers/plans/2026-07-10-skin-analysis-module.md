# Module d'analyse de peau — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Analyse de peau sur 4 photos (Face++ Phase 1) avec scores 0–100 sur 7 conditions, type de peau, recommandations produits depuis `visage_products`, endpoint `/v1/skin/analyze` protégé JWT, et affichage Flutter.

**Architecture:** Nouveau package `backend/app/skin/` avec une interface `SkinAnalyzer` et deux moteurs (`FaceppAnalyzer` fonctionnel, `LocalAnalyzer` scaffold Phase 2), sélectionnés par `ANALYSIS_ENGINE`. Le cœur (parser, agrégation, recommandation) est en fonctions pures testées sans réseau ni DB. Côté Flutter, le flux de capture existant envoie les 4 photos et affiche un nouvel écran résultat.

**Tech Stack:** FastAPI, SQLAlchemy **synchrone** (comme l'existant), Pydantic v2, httpx (async, appel Face++ uniquement), OpenCV/InsightFace (déjà présents), pytest + pytest-asyncio. Flutter : http + http_parser + Riverpod (déjà présents).

**Spec:** `docs/superpowers/specs/2026-07-10-skin-analysis-module-design.md`

## Global Constraints

- Chaînes visibles utilisateur et docstrings **en français** (convention du repo).
- SQLAlchemy **synchrone** partout (pas d'async DB) ; seul l'appel HTTP Face++ est async.
- Photos traitées **en mémoire uniquement** — jamais écrites sur disque ni en base (RGPD).
- Disclaimer obligatoire dans chaque réponse API et sur l'écran résultat : `Cette analyse est indicative et ne remplace pas un avis dermatologique.`
- Routes préfixées `/v1` (pas `/api/v1`).
- Codes conditions : `wrinkles, dark_circles, blackheads, enlarged_pores, dark_spots, redness, acne`. Types de peau : `oily, dry, combination, normal`.
- Seuil de recommandation : score ≥ **30**. Bandes de sévérité : `<30 mild`, `30–59 moderate`, `≥60 severe`. Score de base type de peau : **40**. Top **6** produits.
- `ANALYSIS_ENGINE` défaut : `facepp` (`auto` recommandé seulement après Phase 2).
- Tests backend : `cd backend` puis `python -m pytest tests -v`. Frontend : `cd frontend` puis `flutter analyze` / `flutter test`.
- Commits fréquents, un par tâche, message conventionnel FR comme l'historique (`feat(backend): …`), terminé par `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Socle du module — types unifiés, exceptions, libellés FR, outillage pytest

**Files:**
- Create: `backend/app/skin/__init__.py` (vide)
- Create: `backend/app/skin/analyzer.py`
- Create: `backend/app/skin/labels.py`
- Create: `backend/pytest.ini`
- Create: `backend/requirements-dev.txt`
- Modify: `backend/requirements.txt` (ajouter httpx)
- Test: `backend/tests/test_labels.py`

**Interfaces:**
- Produces: `CONDITION_CODES: list[str]`, `SkinPhotoResult(scores: dict[str,int], skin_type: str, zones: dict[str,list[str]])`, `SkinAnalyzer` (ABC, `async analyze_photo(image_bytes: bytes) -> SkinPhotoResult`), exceptions `SkinEngineError(message_fr)`, `EngineUnavailableError`, `FaceppQuotaError`, `FaceppUnavailableError`, `NoFaceError`, `FrontPhotoFailedError` ; `labels.LABELS_FR`, `labels.severity(score)->str`, `labels.RECOMMEND_THRESHOLD=30`, `labels.DISCLAIMER_FR`.

- [ ] **Step 1: Outillage**

`backend/pytest.ini` :

```ini
[pytest]
asyncio_mode = auto
testpaths = tests
```

`backend/requirements-dev.txt` :

```text
pytest>=8.0
pytest-asyncio>=0.23
```

Ajouter à la fin de `backend/requirements.txt` :

```text

# Analyse de peau (appel Face++ async)
httpx>=0.27
```

Installer : `cd backend && pip install -r requirements-dev.txt && pip install httpx>=0.27`

- [ ] **Step 2: Écrire le test qui échoue**

`backend/tests/test_labels.py` :

```python
"""Tests des libellés FR et des bandes de sévérité."""
from app.skin import labels
from app.skin.analyzer import CONDITION_CODES


def test_toutes_les_conditions_ont_un_libelle():
    assert set(labels.LABELS_FR) == set(CONDITION_CODES)


def test_bandes_de_severite():
    assert labels.severity(0) == "mild"
    assert labels.severity(29) == "mild"
    assert labels.severity(30) == "moderate"
    assert labels.severity(59) == "moderate"
    assert labels.severity(60) == "severe"
    assert labels.severity(100) == "severe"
```

- [ ] **Step 3: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_labels.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin'`

- [ ] **Step 4: Implémenter**

`backend/app/skin/__init__.py` : fichier vide.

`backend/app/skin/analyzer.py` :

```python
"""Contrat commun des moteurs d'analyse de peau (Phase 1 Face++, Phase 2 local)."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

# Les 7 conditions analysées, scores 0-100.
CONDITION_CODES = [
    "wrinkles",
    "dark_circles",
    "blackheads",
    "enlarged_pores",
    "dark_spots",
    "redness",
    "acne",
]

SKIN_TYPES = ["oily", "dry", "combination", "normal"]


class SkinEngineError(Exception):
    """Erreur moteur porteuse d'un message FR affichable."""

    def __init__(self, message_fr: str):
        super().__init__(message_fr)
        self.message_fr = message_fr


class EngineUnavailableError(SkinEngineError):
    """Le moteur ne peut pas fonctionner (quota, clés, dépendances) -> repli/502."""


class FaceppQuotaError(EngineUnavailableError):
    """Quota / authentification Face++ épuisés ou invalides."""


class FaceppUnavailableError(EngineUnavailableError):
    """Face++ injoignable (timeout, 5xx, réponse invalide)."""


class NoFaceError(SkinEngineError):
    """La photo n'est pas exploitable (pas de visage frontal, image invalide)."""


class FrontPhotoFailedError(SkinEngineError):
    """La photo de face (obligatoire) n'a pas pu être analysée -> 422."""


@dataclass
class SkinPhotoResult:
    """Résultat unifié pour UNE photo."""

    scores: dict[str, int]  # condition_code -> 0..100
    skin_type: str  # oily | dry | combination | normal
    zones: dict[str, list[str]] = field(default_factory=dict)


class SkinAnalyzer(ABC):
    """Interface commune aux moteurs (Face++ / local)."""

    name: str = "abstract"

    @abstractmethod
    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        """Analyse une photo. Lève NoFaceError ou EngineUnavailableError."""
```

`backend/app/skin/labels.py` :

```python
"""Libellés français, bandes de sévérité et disclaimer médical."""
from __future__ import annotations

LABELS_FR = {
    "wrinkles": "Rides & ridules",
    "dark_circles": "Cernes",
    "blackheads": "Points noirs",
    "enlarged_pores": "Pores dilatés",
    "dark_spots": "Taches brunes",
    "redness": "Rougeurs / rosacée",
    "acne": "Acné / boutons",
}

SKIN_TYPE_LABELS_FR = {
    "oily": "Peau grasse",
    "dry": "Peau sèche",
    "combination": "Peau mixte",
    "normal": "Peau normale",
}

DISCLAIMER_FR = (
    "Cette analyse est indicative et ne remplace pas un avis dermatologique."
)

# En dessous de ce score, une condition n'entraîne pas de recommandation.
RECOMMEND_THRESHOLD = 30


def severity(score: int) -> str:
    """Bande de sévérité du contrat API : mild | moderate | severe."""
    if score >= 60:
        return "severe"
    if score >= RECOMMEND_THRESHOLD:
        return "moderate"
    return "mild"
```

- [ ] **Step 5: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_labels.py -v`
Expected: 2 PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/skin backend/tests/test_labels.py backend/pytest.ini backend/requirements-dev.txt backend/requirements.txt
git commit -m "feat(backend): socle module skin — types unifiés, libellés FR, pytest"
```

---

### Task 2: Parser Face++ → schéma unifié

**Files:**
- Create: `backend/app/skin/facepp.py`
- Create: `backend/tests/samples.py` (fixture JSON partagée)
- Test: `backend/tests/test_facepp_parser.py`

**Interfaces:**
- Consumes: `SkinPhotoResult`, exceptions de `app.skin.analyzer` (Task 1).
- Produces: `parse_skinanalyze(result: dict) -> SkinPhotoResult` ; constantes `WRINKLE_FIELDS`, `PORE_FIELDS`, `SKIN_TYPE_MAP`, `FACEPP_ENDPOINT_DEFAULT` ; fixture `tests/samples.py::FACEPP_SAMPLE_RESULT`.

- [ ] **Step 1: Fixture partagée**

`backend/tests/samples.py` :

```python
"""Bloc `result` d'exemple de l'API Face++ Skin Analyze (format documenté v1)."""

FACEPP_SAMPLE_RESULT = {
    "skin_type": {
        "skin_type": 0,  # 0=grasse, 1=sèche, 2=normale, 3=mixte
        "details": {
            "0": {"value": 1, "confidence": 0.89},
            "1": {"value": 0, "confidence": 0.05},
            "2": {"value": 0, "confidence": 0.04},
            "3": {"value": 0, "confidence": 0.02},
        },
    },
    "acne": {"value": 1, "confidence": 0.62},
    "blackhead": {"value": 1, "confidence": 0.55},
    "skin_spot": {"value": 0, "confidence": 0.88},
    "dark_circle": {"value": 1, "confidence": 0.71},
    "forehead_wrinkle": {"value": 0, "confidence": 0.93},
    "crows_feet": {"value": 1, "confidence": 0.44},
    "eye_finelines": {"value": 0, "confidence": 0.80},
    "glabella_wrinkle": {"value": 0, "confidence": 0.85},
    "nasolabial_fold": {"value": 1, "confidence": 0.52},
    "pores_forehead": {"value": 1, "confidence": 0.66},
    "pores_left_cheek": {"value": 0, "confidence": 0.90},
    "pores_right_cheek": {"value": 0, "confidence": 0.84},
    "pores_jaw": {"value": 1, "confidence": 0.58},
}
```

- [ ] **Step 2: Écrire le test qui échoue**

`backend/tests/test_facepp_parser.py` :

```python
"""Tests du parser Face++ -> schéma unifié (aucun appel réseau)."""
from app.skin.facepp import parse_skinanalyze
from samples import FACEPP_SAMPLE_RESULT


def test_scores_unifies():
    r = parse_skinanalyze(FACEPP_SAMPLE_RESULT)
    assert r.scores["acne"] == 62          # présent -> confiance*100
    assert r.scores["blackheads"] == 55
    assert r.scores["dark_spots"] == 12    # absent -> (1-confiance)*100
    assert r.scores["dark_circles"] == 71
    assert r.scores["wrinkles"] == 52      # max des 5 sous-indicateurs
    assert r.scores["enlarged_pores"] == 38  # moyenne des 4 zones
    assert r.scores["redness"] == 0        # non fourni par Face++ (Phase 2)


def test_zones():
    r = parse_skinanalyze(FACEPP_SAMPLE_RESULT)
    assert r.zones["wrinkles"] == ["eyes", "nasolabial"]
    assert r.zones["enlarged_pores"] == ["forehead", "chin"]
    assert r.zones["dark_circles"] == ["eyes"]


def test_type_de_peau():
    assert parse_skinanalyze(FACEPP_SAMPLE_RESULT).skin_type == "oily"


def test_champs_absents_tolerants():
    r = parse_skinanalyze({})
    assert r.skin_type == "normal"
    assert all(v == 0 for v in r.scores.values())
```

- [ ] **Step 3: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_facepp_parser.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.facepp'`

- [ ] **Step 4: Implémenter**

`backend/app/skin/facepp.py` :

```python
"""Moteur Face++ Skin Analyze : parser vers le schéma unifié (+ client HTTP en Task 3)."""
from __future__ import annotations

from .analyzer import SkinPhotoResult

FACEPP_ENDPOINT_DEFAULT = "https://api-us.faceplusplus.com/facepp/v1/skinanalyze"

# Sous-indicateurs de rides -> zone du visage.
WRINKLE_FIELDS = {
    "forehead_wrinkle": "forehead",
    "crows_feet": "eyes",
    "eye_finelines": "eyes",
    "glabella_wrinkle": "glabella",
    "nasolabial_fold": "nasolabial",
}

# Pores par zone.
PORE_FIELDS = {
    "pores_forehead": "forehead",
    "pores_left_cheek": "left_cheek",
    "pores_right_cheek": "right_cheek",
    "pores_jaw": "chin",
}

SKIN_TYPE_MAP = {0: "oily", 1: "dry", 2: "normal", 3: "combination"}


def _indicator_score(field: dict | None) -> int:
    """`{'value': 0|1, 'confidence': c}` -> score 0-100.

    Présent : la confiance devient le score ; absent : plus la confiance est
    haute, plus le score est bas.
    """
    if not field:
        return 0
    confidence = float(field.get("confidence", 0.0))
    present = int(field.get("value", 0)) == 1
    return round(confidence * 100) if present else round((1 - confidence) * 100)


def _present(field: dict | None) -> bool:
    return bool(field) and int(field.get("value", 0)) == 1


def parse_skinanalyze(result: dict) -> SkinPhotoResult:
    """Convertit le bloc `result` de Face++ vers le schéma unifié."""
    scores: dict[str, int] = {}
    zones: dict[str, list[str]] = {}

    scores["wrinkles"] = max(_indicator_score(result.get(f)) for f in WRINKLE_FIELDS)
    wrinkle_zones = [z for f, z in WRINKLE_FIELDS.items() if _present(result.get(f))]
    if wrinkle_zones:
        zones["wrinkles"] = list(dict.fromkeys(wrinkle_zones))

    pore_scores = [_indicator_score(result.get(f)) for f in PORE_FIELDS]
    scores["enlarged_pores"] = round(sum(pore_scores) / len(pore_scores))
    pore_zones = [z for f, z in PORE_FIELDS.items() if _present(result.get(f))]
    if pore_zones:
        zones["enlarged_pores"] = pore_zones

    scores["acne"] = _indicator_score(result.get("acne"))
    scores["blackheads"] = _indicator_score(result.get("blackhead"))
    scores["dark_spots"] = _indicator_score(result.get("skin_spot"))
    scores["dark_circles"] = _indicator_score(result.get("dark_circle"))
    if _present(result.get("dark_circle")):
        zones["dark_circles"] = ["eyes"]

    # Face++ ne renvoie pas les rougeurs : calculées par le moteur local (Phase 2).
    scores["redness"] = 0

    raw_type = (result.get("skin_type") or {}).get("skin_type", 2)
    skin_type = SKIN_TYPE_MAP.get(int(raw_type), "normal")

    return SkinPhotoResult(scores=scores, skin_type=skin_type, zones=zones)
```

- [ ] **Step 5: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_facepp_parser.py -v`
Expected: 4 PASS

- [ ] **Step 6: Commit**

```bash
git add backend/app/skin/facepp.py backend/tests/samples.py backend/tests/test_facepp_parser.py
git commit -m "feat(backend): parser Face++ skinanalyze vers schéma unifié"
```

---

### Task 3: Client HTTP FaceppAnalyzer (retry + classification d'erreurs)

**Files:**
- Modify: `backend/app/skin/facepp.py` (ajouter la classe en fin de fichier)
- Test: `backend/tests/test_facepp_analyzer.py`

**Interfaces:**
- Consumes: `parse_skinanalyze`, exceptions Task 1, fixture `FACEPP_SAMPLE_RESULT`.
- Produces: `FaceppAnalyzer(api_key=None, api_secret=None, endpoint=None, timeout=15.0)` avec `name="facepp"`, `async analyze_photo(bytes) -> SkinPhotoResult`, méthode interne `_post(image_bytes) -> httpx.Response` (monkeypatchable).

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_facepp_analyzer.py` :

```python
"""Tests du client Face++ (API mockée via _post, aucun appel réseau)."""
import httpx
import pytest

from app.skin.analyzer import FaceppQuotaError, FaceppUnavailableError, NoFaceError
from app.skin.facepp import FaceppAnalyzer
from samples import FACEPP_SAMPLE_RESULT


def _response(payload: dict, status: int = 200) -> httpx.Response:
    return httpx.Response(
        status, json=payload, request=httpx.Request("POST", "https://facepp.test")
    )


def _analyzer() -> FaceppAnalyzer:
    return FaceppAnalyzer(api_key="k", api_secret="s")


async def test_cles_absentes():
    analyzer = FaceppAnalyzer(api_key="", api_secret="")
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")


async def test_quota_epuise(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"error_message": "CONCURRENCY_LIMIT_EXCEEDED"}, status=403)

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppQuotaError):
        await analyzer.analyze_photo(b"x")


async def test_pas_de_visage(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"error_message": "NO_FACE_FOUND"}, status=400)

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(NoFaceError):
        await analyzer.analyze_photo(b"x")


async def test_reponse_valide(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"result": FACEPP_SAMPLE_RESULT})

    monkeypatch.setattr(analyzer, "_post", fake_post)
    result = await analyzer.analyze_photo(b"x")
    assert result.scores["acne"] == 62
    assert result.skin_type == "oily"


async def test_timeout_deux_tentatives(monkeypatch):
    analyzer = _analyzer()
    calls: list[int] = []

    async def fake_post(image_bytes):
        calls.append(1)
        raise httpx.ConnectTimeout("boom")

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")
    assert len(calls) == 2  # 1 essai + 1 retry
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_facepp_analyzer.py -v`
Expected: FAIL — `ImportError: cannot import name 'FaceppAnalyzer'`

- [ ] **Step 3: Implémenter**

Dans `backend/app/skin/facepp.py`, compléter les imports en tête :

```python
import os

import httpx

from .analyzer import (
    FaceppQuotaError,
    FaceppUnavailableError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)
```

Puis ajouter en fin de fichier :

```python
_QUOTA_KEYWORDS = ("LIMIT", "BALANCE", "AUTH")


def _raise_for_facepp_error(error_message: str) -> None:
    """Classe l'erreur Face++ : quota/clés, photo inexploitable, ou autre."""
    upper = error_message.upper()
    if any(keyword in upper for keyword in _QUOTA_KEYWORDS):
        raise FaceppQuotaError(
            "Service d'analyse temporairement indisponible (quota Face++)."
        )
    if "FACE" in upper or "IMAGE" in upper:
        raise NoFaceError("visage non exploitable par le service d'analyse.")
    raise FaceppUnavailableError(f"Erreur du service d'analyse : {error_message}")


class FaceppAnalyzer(SkinAnalyzer):
    """Moteur Phase 1 : API Face++ Skin Analyze (visage frontal requis)."""

    name = "facepp"

    def __init__(
        self,
        api_key: str | None = None,
        api_secret: str | None = None,
        endpoint: str | None = None,
        timeout: float = 15.0,
    ):
        self.api_key = api_key if api_key is not None else os.getenv("FACEPP_API_KEY", "")
        self.api_secret = (
            api_secret if api_secret is not None else os.getenv("FACEPP_API_SECRET", "")
        )
        self.endpoint = endpoint or os.getenv("FACEPP_ENDPOINT", FACEPP_ENDPOINT_DEFAULT)
        self.timeout = timeout

    async def _post(self, image_bytes: bytes) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            return await client.post(
                self.endpoint,
                data={"api_key": self.api_key, "api_secret": self.api_secret},
                files={"image_file": ("photo.jpg", image_bytes, "image/jpeg")},
            )

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        if not self.api_key or not self.api_secret:
            raise FaceppUnavailableError(
                "Clés Face++ manquantes (FACEPP_API_KEY / FACEPP_API_SECRET)."
            )
        for _attempt in (1, 2):  # 1 essai + 1 retry sur timeout / 5xx
            try:
                response = await self._post(image_bytes)
            except httpx.TimeoutException:
                continue
            if response.status_code >= 500:
                continue
            payload = response.json()
            error_message = payload.get("error_message")
            if error_message:
                _raise_for_facepp_error(error_message)
            result = payload.get("result")
            if result is None:
                raise FaceppUnavailableError("Réponse Face++ sans bloc result.")
            return parse_skinanalyze(result)
        raise FaceppUnavailableError(
            "Service d'analyse injoignable (délai dépassé après 2 tentatives)."
        )
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_facepp_analyzer.py tests/test_facepp_parser.py -v`
Expected: 9 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/facepp.py backend/tests/test_facepp_analyzer.py
git commit -m "feat(backend): client Face++ avec retry et erreurs classifiées"
```

---

### Task 4: Validation qualité des photos

**Files:**
- Modify: `backend/app/vision.py` (ajouter `count_faces` à la fin)
- Create: `backend/app/skin/quality.py`
- Test: `backend/tests/test_quality.py`

**Interfaces:**
- Consumes: `vision._face_app` via nouvelle fonction publique.
- Produces: `vision.count_faces(img_bgr) -> int | None` (None = modèle non chargé) ; `quality.validate_photo(raw: bytes, photo_name: str) -> None` qui lève `quality.PhotoQualityError(message_fr)`.

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_quality.py` :

```python
"""Tests de la validation qualité (images synthétiques, modèle CV non chargé)."""
import cv2
import numpy as np
import pytest

from app.skin.quality import PhotoQualityError, validate_photo


def _jpeg(img: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def test_octets_invalides_rejetes():
    with pytest.raises(PhotoQualityError, match="illisible"):
        validate_photo(b"pas-une-image", "front")


def test_photo_noire_rejetee():
    raw = _jpeg(np.zeros((300, 300, 3), np.uint8))
    with pytest.raises(PhotoQualityError, match="sombre"):
        validate_photo(raw, "front")


def test_photo_uniforme_rejetee_car_floue():
    raw = _jpeg(np.full((300, 300, 3), 128, np.uint8))
    with pytest.raises(PhotoQualityError, match="floue"):
        validate_photo(raw, "left")


def test_photo_contrastee_acceptee():
    # Bruit aléatoire : luminosité moyenne ~127, forte variance Laplacienne.
    # Le comptage de visages est sauté car le modèle CV n'est pas chargé en test.
    rng = np.random.default_rng(42)
    img = rng.integers(0, 256, size=(300, 300, 3)).astype(np.uint8)
    validate_photo(_jpeg(img), "front")  # ne doit pas lever
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_quality.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.quality'`

- [ ] **Step 3: Implémenter**

Ajouter à la fin de `backend/app/vision.py` :

```python
def count_faces(img_bgr: np.ndarray) -> int | None:
    """Nombre de visages détectés, ou None si le modèle n'est pas chargé."""
    if _face_app is None:
        return None
    return len(_face_app.get(img_bgr))
```

`backend/app/skin/quality.py` :

```python
"""Validation qualité d'une photo avant analyse : lisibilité, luminosité, flou, visages.

Le comptage de visages réutilise InsightFace chargé au démarrage (vision.py) ;
si le modèle n'est pas disponible, cette vérification est sautée.
"""
from __future__ import annotations

import os

import cv2
import numpy as np

from .. import vision


class PhotoQualityError(ValueError):
    """Photo rejetée — porte un message FR affichable (préfixé du nom de la photo)."""

    def __init__(self, message_fr: str):
        super().__init__(message_fr)
        self.message_fr = message_fr


BRIGHTNESS_MIN = 40.0
BRIGHTNESS_MAX = 220.0


def _blur_threshold() -> float:
    return float(os.getenv("SKIN_BLUR_THRESHOLD", "60"))


def validate_photo(raw: bytes, photo_name: str) -> None:
    """Lève PhotoQualityError si la photo est inutilisable pour l'analyse."""
    arr = np.frombuffer(raw, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise PhotoQualityError(f"{photo_name} : image illisible.")

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    brightness = float(gray.mean())
    if brightness < BRIGHTNESS_MIN:
        raise PhotoQualityError(f"{photo_name} : photo trop sombre.")
    if brightness > BRIGHTNESS_MAX:
        raise PhotoQualityError(f"{photo_name} : photo surexposée.")

    blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    if blur < _blur_threshold():
        raise PhotoQualityError(f"{photo_name} : photo floue.")

    nb_faces = vision.count_faces(img)
    if nb_faces is None:
        return  # modèle CV non chargé : vérification visage sautée
    if nb_faces == 0:
        raise PhotoQualityError(f"{photo_name} : aucun visage détecté.")
    if nb_faces > 1:
        raise PhotoQualityError(f"{photo_name} : plusieurs visages détectés.")
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_quality.py -v`
Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/vision.py backend/app/skin/quality.py backend/tests/test_quality.py
git commit -m "feat(backend): validation qualité photos (flou, luminosité, visages)"
```

---

### Task 5: Agrégation multi-photos

**Files:**
- Create: `backend/app/skin/aggregate.py`
- Test: `backend/tests/test_aggregate.py`

**Interfaces:**
- Consumes: `CONDITION_CODES`, `SkinPhotoResult` (Task 1).
- Produces: `aggregate(results: dict[str, SkinPhotoResult]) -> tuple[dict[str, int], str, dict[str, list[str]]]` (scores max, type de peau voté, zones fusionnées) ; constante `FRONT_KEY = "front"`.

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_aggregate.py` :

```python
"""Tests de l'agrégation : max par condition, union des zones, vote majoritaire."""
import pytest

from app.skin.aggregate import aggregate
from app.skin.analyzer import CONDITION_CODES, SkinPhotoResult


def _photo(skin_type: str = "oily", **overrides) -> SkinPhotoResult:
    scores = {c: 0 for c in CONDITION_CODES}
    scores.update(overrides.pop("scores", {}))
    return SkinPhotoResult(scores=scores, skin_type=skin_type, **overrides)


def test_max_par_condition_et_union_zones():
    results = {
        "front": _photo(scores={"acne": 40}, zones={"acne": ["chin"]}),
        "left": _photo(scores={"acne": 62}, zones={"acne": ["left_cheek", "chin"]}),
    }
    scores, _, zones = aggregate(results)
    assert scores["acne"] == 62
    assert scores["wrinkles"] == 0
    assert zones["acne"] == ["chin", "left_cheek"]


def test_vote_majoritaire_type_de_peau():
    results = {
        "front": _photo("dry"),
        "left": _photo("oily"),
        "right": _photo("oily"),
    }
    _, skin_type, _ = aggregate(results)
    assert skin_type == "oily"


def test_egalite_tranchee_par_la_photo_de_face():
    results = {
        "front": _photo("dry"),
        "left": _photo("oily"),
        "right": _photo("oily"),
        "closeup": _photo("dry"),
    }
    _, skin_type, _ = aggregate(results)
    assert skin_type == "dry"


def test_agregation_vide_interdite():
    with pytest.raises(ValueError):
        aggregate({})
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_aggregate.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.aggregate'`

- [ ] **Step 3: Implémenter**

`backend/app/skin/aggregate.py` :

```python
"""Agrégation des résultats par photo -> résultat global de l'analyse."""
from __future__ import annotations

from collections import Counter

from .analyzer import CONDITION_CODES, SkinPhotoResult

FRONT_KEY = "front"


def aggregate(
    results: dict[str, SkinPhotoResult],
) -> tuple[dict[str, int], str, dict[str, list[str]]]:
    """Max du score par condition, union des zones, vote majoritaire du type.

    `results` ne contient que les photos analysées avec succès ; la photo de
    face (`front`) est garantie présente par le moteur. En cas d'égalité au
    vote, le type de la photo de face l'emporte.
    """
    if not results:
        raise ValueError("aucun résultat photo à agréger")

    scores = {
        code: max(r.scores.get(code, 0) for r in results.values())
        for code in CONDITION_CODES
    }

    zones: dict[str, list[str]] = {}
    for result in results.values():
        for condition, zone_list in result.zones.items():
            bucket = zones.setdefault(condition, [])
            for zone in zone_list:
                if zone not in bucket:
                    bucket.append(zone)

    votes = Counter(r.skin_type for r in results.values()).most_common()
    if len(votes) > 1 and votes[0][1] == votes[1][1] and FRONT_KEY in results:
        skin_type = results[FRONT_KEY].skin_type
    else:
        skin_type = votes[0][0]

    return scores, skin_type, zones
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_aggregate.py -v`
Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/aggregate.py backend/tests/test_aggregate.py
git commit -m "feat(backend): agrégation multi-photos (max, zones, vote type de peau)"
```

---

### Task 6: Modèles DB + script de seed

**Files:**
- Modify: `backend/app/models.py` (ajouter 3 modèles à la fin + imports)
- Create: `backend/scripts/seed_condition_map.py`
- Create: `backend/tests/conftest.py` (fixture sqlite partagée)
- Test: `backend/tests/test_seed.py`

**Interfaces:**
- Produces: modèles `SkinAnalysis` (table `skin_analyses`), `ConditionProductMap` (table `condition_product_map`), `VisageProduct` (mapping lecture seule de `visage_products`, colonnes utiles uniquement — **pas** les colonnes ARRAY, pour rester compatible sqlite en test) ; `scripts.seed_condition_map.seed(db) -> int` et `main()` ; fixture pytest `db_session`.

- [ ] **Step 1: Fixture sqlite**

`backend/tests/conftest.py` :

```python
"""Fixtures partagées : session SQLAlchemy sur sqlite en mémoire."""
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base


@pytest.fixture()
def db_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSession = sessionmaker(bind=engine)
    session = TestingSession()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()
```

- [ ] **Step 2: Écrire les tests qui échouent**

`backend/tests/test_seed.py` :

```python
"""Tests du seed de condition_product_map depuis les slugs `sub`."""
from app.models import ConditionProductMap, VisageProduct
from scripts.seed_condition_map import CONDITION_SUBS, seed


def _produit(pid: int, sub: str) -> VisageProduct:
    return VisageProduct(
        id=pid, sub=sub, name=f"Produit {pid}", brand="Marque",
        price=10.0, in_stock=True, active=True,
    )


def test_seed_mappe_les_sous_categories(db_session):
    db_session.add_all([
        _produit(1, "soins-anti-age-rides"),
        _produit(2, "soins-peau-grasse-mixte-acne"),
        _produit(3, "maquillage"),  # non mappé
    ])
    db_session.commit()

    total = seed(db_session)

    rows = db_session.query(ConditionProductMap).all()
    assert total == len(rows)
    codes = {(r.condition_code, r.product_id) for r in rows}
    assert ("wrinkles", 1) in codes
    assert ("acne", 2) in codes
    # le produit 2 sert aussi blackheads et enlarged_pores (priorité moindre)
    assert ("blackheads", 2) in codes
    assert ("enlarged_pores", 2) in codes
    assert all(pid != 3 for _, pid in codes)


def test_seed_idempotent(db_session):
    db_session.add(_produit(1, "soins-anti-age-rides"))
    db_session.commit()
    first = seed(db_session)
    second = seed(db_session)
    assert first == second == db_session.query(ConditionProductMap).count()


def test_toutes_les_conditions_du_seed_ont_des_slugs():
    for condition, subs in CONDITION_SUBS.items():
        assert subs, f"{condition} sans slug"
```

- [ ] **Step 3: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_seed.py -v`
Expected: FAIL — `ImportError: cannot import name 'ConditionProductMap'`

- [ ] **Step 4: Implémenter les modèles**

Dans `backend/app/models.py`, étendre l'import SQLAlchemy existant :

```python
from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    LargeBinary,
    Numeric,
    String,
    Text,
    func,
)
```

Ajouter à la fin du fichier :

```python
class SkinAnalysis(Base):
    """Une analyse de peau (4 photos) — seuls les résultats JSON sont stockés."""

    __tablename__ = "skin_analyses"

    id = Column(Integer, primary_key=True)
    pharmacy_id = Column(
        Integer, ForeignKey("pharmacies.id"), nullable=False, index=True
    )
    client_id = Column(Integer, ForeignKey("clients.id"), nullable=True, index=True)
    skin_type = Column(String, nullable=False)
    results_json = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ConditionProductMap(Base):
    """Mapping condition (ou skin_type_*) -> produit recommandable."""

    __tablename__ = "condition_product_map"

    id = Column(Integer, primary_key=True)
    condition_code = Column(String(30), nullable=False, index=True)
    skin_type = Column(String(15), nullable=True)  # NULL = tout type de peau
    product_id = Column(Integer, ForeignKey("visage_products.id"), nullable=False)
    priority = Column(Integer, nullable=False, default=0)


class VisageProduct(Base):
    """Mapping lecture seule du catalogue existant (colonnes utilisées seulement).

    La table réelle a plus de colonnes (dont des ARRAY PostgreSQL) : on ne
    mappe que ce dont le module skin a besoin, ce qui garde les tests
    compatibles sqlite. `create_all` ne modifie jamais une table existante.
    """

    __tablename__ = "visage_products"

    id = Column(Integer, primary_key=True)
    sub = Column(Text)
    brand = Column(Text)
    name = Column(Text)
    description = Column(Text)
    price = Column(Numeric)
    image_url = Column(Text)
    in_stock = Column(Boolean)
    active = Column(Boolean)
```

- [ ] **Step 5: Implémenter le seed**

`backend/scripts/seed_condition_map.py` :

```python
"""Seed de condition_product_map depuis les slugs `sub` de visage_products.

Idempotent : vide la table puis réinsère. Usage (depuis backend/) :
    python -m scripts.seed_condition_map
"""
from __future__ import annotations

from app.db import Base, SessionLocal, engine
from app.models import ConditionProductMap, VisageProduct

# condition -> [(slug de sous-catégorie, priorité)]
CONDITION_SUBS: dict[str, list[tuple[str, int]]] = {
    "wrinkles": [("soins-anti-age-rides", 10)],
    "dark_spots": [
        ("soins-anti-taches-depigmentants", 10),
        ("soins-eclaircissants", 5),
    ],
    "acne": [("soins-peau-grasse-mixte-acne", 10)],
    "redness": [
        ("soins-anti-rougeurs-sensible", 10),
        ("soins-apaisants", 7),
        ("eaux-thermales", 4),
    ],
    "dark_circles": [("yeux-levres", 10)],
    "blackheads": [
        ("masques-gommages", 8),
        ("soins-peau-grasse-mixte-acne", 6),
    ],
    "enlarged_pores": [
        ("masques-gommages", 8),
        ("soins-peau-grasse-mixte-acne", 6),
    ],
    # Recommandations de base liées au type de peau détecté.
    "skin_type_dry": [
        ("peaux-seches", 10),
        ("soins-hydratants-nourrissants", 6),
    ],
    "skin_type_oily": [("demaquillants-nettoyants", 5)],
}


def seed(db) -> int:
    """Vide puis repeuple la table. Renvoie le nombre de lignes insérées."""
    db.query(ConditionProductMap).delete()
    total = 0
    for condition, subs in CONDITION_SUBS.items():
        for sub, priority in subs:
            product_ids = [
                row[0]
                for row in db.query(VisageProduct.id)
                .filter(VisageProduct.sub == sub)
                .all()
            ]
            db.add_all(
                ConditionProductMap(
                    condition_code=condition, product_id=pid, priority=priority
                )
                for pid in product_ids
            )
            total += len(product_ids)
    db.commit()
    return total


def main() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        print(f"{seed(db)} lignes insérées dans condition_product_map.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_seed.py -v`
Expected: 3 PASS

- [ ] **Step 7: Commit**

```bash
git add backend/app/models.py backend/scripts/seed_condition_map.py backend/tests/conftest.py backend/tests/test_seed.py
git commit -m "feat(backend): tables skin_analyses + condition_product_map + seed depuis sub"
```

---

### Task 7: Moteur de recommandation

**Files:**
- Create: `backend/app/skin/recommend.py`
- Test: `backend/tests/test_recommend.py`

**Interfaces:**
- Consumes: `labels.RECOMMEND_THRESHOLD`, `labels.severity` (Task 1) ; modèles `ConditionProductMap`, `VisageProduct` (Task 6).
- Produces: `Recommendation` (dataclass : `product_id, name, brand, price, image_url, reason_fr, matched_conditions`) ; `build_recommendations(scores: dict[str,int], skin_type: str, mappings: list[dict], products: dict[int, dict]) -> list[Recommendation]` (pur) ; `build_reason_fr(matched, scores, skin_type) -> str` ; `fetch_mappings(db, condition_codes) -> list[dict]` ; `fetch_products(db, product_ids) -> dict[int, dict]` ; constantes `SKIN_TYPE_BASE_SCORE = 40`, `TOP_N = 6`.

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_recommend.py` :

```python
"""Tests du moteur de recommandation (cœur pur + fetchers sqlite)."""
from app.models import ConditionProductMap, VisageProduct
from app.skin.recommend import (
    build_reason_fr,
    build_recommendations,
    fetch_mappings,
    fetch_products,
)


def _products(n: int) -> dict[int, dict]:
    return {
        i: {
            "name": f"Produit {i}", "brand": "Marque", "price": 10.0 + i,
            "image_url": None, "in_stock": True, "active": True,
        }
        for i in range(1, n + 1)
    }


def _mapping(cond: str, pid: int, priority: int = 10, skin_type: str | None = None):
    return {
        "condition_code": cond, "product_id": pid,
        "priority": priority, "skin_type": skin_type,
    }


SCORES = {
    "acne": 62, "wrinkles": 25, "dark_spots": 45, "dark_circles": 0,
    "blackheads": 0, "enlarged_pores": 0, "redness": 0,
}


def test_seuil_et_rang():
    mappings = [
        _mapping("acne", 1, 10),
        _mapping("acne", 2, 5),
        _mapping("dark_spots", 2, 10),
        _mapping("wrinkles", 3, 10),  # 25 < 30 : jamais recommandé
        _mapping("skin_type_oily", 4, 5),
    ]
    recs = build_recommendations(SCORES, "oily", mappings, _products(4))
    ids = [r.product_id for r in recs]
    # p2 = 62*5 + 45*10 = 760 > p1 = 620 > p4 = 40*5 = 200 ; p3 exclu.
    assert ids == [2, 1, 4]
    assert recs[0].matched_conditions == ["acne", "dark_spots"]
    assert recs[2].matched_conditions == []  # match uniquement type de peau


def test_filtre_type_de_peau():
    mappings = [
        _mapping("acne", 1, 10, skin_type="dry"),   # incompatible
        _mapping("acne", 2, 10, skin_type="oily"),  # compatible
        _mapping("acne", 3, 10, skin_type=None),    # tout type
    ]
    ids = [r.product_id for r in build_recommendations(SCORES, "oily", mappings, _products(3))]
    assert 1 not in ids and set(ids) == {2, 3}


def test_produits_inactifs_ou_epuises_exclus():
    products = _products(2)
    products[1]["active"] = False
    products[2]["in_stock"] = False
    recs = build_recommendations(
        SCORES, "oily", [_mapping("acne", 1), _mapping("acne", 2)], products
    )
    assert recs == []


def test_top_6():
    mappings = [_mapping("acne", i) for i in range(1, 9)]
    assert len(build_recommendations(SCORES, "oily", mappings, _products(8))) == 6


def test_reason_fr():
    reason = build_reason_fr(["acne", "skin_type_oily"], SCORES, "oily")
    assert reason == "Recommandé pour votre acné marquée et votre peau grasse."
    seul_type = build_reason_fr(["skin_type_dry"], SCORES, "dry")
    assert seul_type == "Recommandé pour votre peau sèche."


def test_fetchers_sqlite(db_session):
    db_session.add(VisageProduct(
        id=1, sub="soins-anti-age-rides", name="Crème", brand="M",
        price=19.9, image_url="http://img", in_stock=True, active=True,
    ))
    db_session.add(ConditionProductMap(condition_code="wrinkles", product_id=1, priority=10))
    db_session.commit()

    mappings = fetch_mappings(db_session, ["wrinkles", "acne"])
    assert mappings == [
        {"condition_code": "wrinkles", "skin_type": None, "product_id": 1, "priority": 10}
    ]
    products = fetch_products(db_session, [1])
    assert products[1]["name"] == "Crème"
    assert products[1]["price"] == 19.9
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_recommend.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.recommend'`

- [ ] **Step 3: Implémenter**

`backend/app/skin/recommend.py` :

```python
"""Moteur de recommandation produits — cœur pur (testable sans DB) + fetchers SQL."""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy.orm import Session

from ..models import ConditionProductMap, VisageProduct
from .labels import RECOMMEND_THRESHOLD, severity

# Score fictif attribué au type de peau détecté (déclenche les produits de base).
SKIN_TYPE_BASE_SCORE = 40
TOP_N = 6

# Tournures FR par condition et par bande de sévérité (accords inclus).
CONDITION_PHRASES_FR = {
    "acne": {"moderate": "votre acné modérée", "severe": "votre acné marquée"},
    "wrinkles": {"moderate": "vos rides modérées", "severe": "vos rides marquées"},
    "dark_circles": {"moderate": "vos cernes modérés", "severe": "vos cernes marqués"},
    "blackheads": {
        "moderate": "vos points noirs modérés",
        "severe": "vos points noirs marqués",
    },
    "enlarged_pores": {
        "moderate": "vos pores dilatés",
        "severe": "vos pores très dilatés",
    },
    "dark_spots": {
        "moderate": "vos taches brunes modérées",
        "severe": "vos taches brunes marquées",
    },
    "redness": {
        "moderate": "vos rougeurs modérées",
        "severe": "vos rougeurs marquées",
    },
}

SKIN_TYPE_PHRASES_FR = {
    "oily": "peau grasse",
    "dry": "peau sèche",
    "combination": "peau mixte",
    "normal": "peau normale",
}


@dataclass
class Recommendation:
    product_id: int
    name: str
    brand: str | None
    price: float | None
    image_url: str | None
    reason_fr: str
    matched_conditions: list[str]


def build_reason_fr(matched: list[str], scores: dict[str, int], skin_type: str) -> str:
    """Ex. « Recommandé pour votre acné modérée et votre peau grasse. »"""
    parts: list[str] = []
    for condition in matched:
        if condition.startswith("skin_type_"):
            continue
        band = severity(scores[condition])  # matched => score >= seuil => pas mild
        phrases = CONDITION_PHRASES_FR.get(condition, {})
        parts.append(phrases.get(band) or phrases.get("moderate") or condition)
    if any(c.startswith("skin_type_") for c in matched) or not parts:
        parts.append("votre " + SKIN_TYPE_PHRASES_FR.get(skin_type, "peau"))
    return "Recommandé pour " + " et ".join(parts) + "."


def build_recommendations(
    scores: dict[str, int],
    skin_type: str,
    mappings: list[dict],
    products: dict[int, dict],
) -> list[Recommendation]:
    """Conditions >= seuil -> produits mappés -> rang (sévérité x priorité) -> top 6."""
    effective = {c: s for c, s in scores.items() if s >= RECOMMEND_THRESHOLD}
    effective[f"skin_type_{skin_type}"] = SKIN_TYPE_BASE_SCORE

    candidates: dict[int, dict] = {}
    for mapping in mappings:
        condition = mapping["condition_code"]
        if condition not in effective:
            continue
        if mapping.get("skin_type") and mapping["skin_type"] != skin_type:
            continue
        product = products.get(mapping["product_id"])
        if not product or not product.get("active") or not product.get("in_stock"):
            continue
        entry = candidates.setdefault(
            mapping["product_id"], {"rank": 0.0, "matched": []}
        )
        # priorité 0 traitée comme 1 pour ne pas annuler le rang.
        entry["rank"] += effective[condition] * max(int(mapping.get("priority") or 0), 1)
        if condition not in entry["matched"]:
            entry["matched"].append(condition)

    ranked = sorted(candidates.items(), key=lambda kv: (-kv[1]["rank"], kv[0]))
    recommendations = []
    for product_id, entry in ranked[:TOP_N]:
        product = products[product_id]
        recommendations.append(
            Recommendation(
                product_id=product_id,
                name=product.get("name") or "",
                brand=product.get("brand"),
                price=product.get("price"),
                image_url=product.get("image_url"),
                reason_fr=build_reason_fr(entry["matched"], scores, skin_type),
                matched_conditions=[
                    c for c in entry["matched"] if not c.startswith("skin_type_")
                ],
            )
        )
    return recommendations


def fetch_mappings(db: Session, condition_codes: list[str]) -> list[dict]:
    """Lignes de condition_product_map pour les conditions données."""
    rows = (
        db.query(ConditionProductMap)
        .filter(ConditionProductMap.condition_code.in_(condition_codes))
        .all()
    )
    return [
        {
            "condition_code": r.condition_code,
            "skin_type": r.skin_type,
            "product_id": r.product_id,
            "priority": r.priority,
        }
        for r in rows
    ]


def fetch_products(db: Session, product_ids: list[int]) -> dict[int, dict]:
    """Produits par id — prix converti en float (colonne Numeric)."""
    if not product_ids:
        return {}
    rows = (
        db.query(VisageProduct).filter(VisageProduct.id.in_(set(product_ids))).all()
    )
    return {
        r.id: {
            "name": r.name,
            "brand": r.brand,
            "price": float(r.price) if r.price is not None else None,
            "image_url": r.image_url,
            "in_stock": bool(r.in_stock),
            "active": bool(r.active),
        }
        for r in rows
    }
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_recommend.py -v`
Expected: 7 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/recommend.py backend/tests/test_recommend.py
git commit -m "feat(backend): moteur de recommandation (seuil, rang, dédup, top 6, reason_fr)"
```

---

### Task 8: Façade moteur (ANALYSIS_ENGINE, repli auto)

**Files:**
- Create: `backend/app/skin/engine.py`
- Test: `backend/tests/test_engine.py`

**Interfaces:**
- Consumes: `FaceppAnalyzer` (Task 3), exceptions et `SkinAnalyzer`/`SkinPhotoResult` (Task 1).
- Produces: `EngineRunResult` (dataclass : `results: dict[str, SkinPhotoResult]`, `photo_status: dict[str, str]`, `engine: str`) ; `async run_analysis(photos: dict[str, bytes], mode: str | None = None) -> EngineRunResult` ; `_make(name: str) -> SkinAnalyzer` (monkeypatchable en test). Le moteur `local` est importé paresseusement (le module n'existe qu'en Task 10 — l'import échoué devient `EngineUnavailableError`).

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_engine.py` :

```python
"""Tests de la façade moteur : tolérance par photo, repli auto, erreurs."""
import pytest

from app.skin import engine
from app.skin.analyzer import (
    CONDITION_CODES,
    FaceppQuotaError,
    FrontPhotoFailedError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)

PHOTOS = {name: name.encode() for name in ["front", "left", "right", "closeup"]}


def _result(skin_type: str = "oily") -> SkinPhotoResult:
    return SkinPhotoResult(
        scores={c: 10 for c in CONDITION_CODES}, skin_type=skin_type
    )


class FakeAnalyzer(SkinAnalyzer):
    name = "fake"

    def __init__(self, no_face: set[str] = frozenset(), fatal: Exception | None = None):
        self.no_face = set(no_face)
        self.fatal = fatal

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        if self.fatal is not None:
            raise self.fatal
        key = image_bytes.decode()
        if key in self.no_face:
            raise NoFaceError(f"{key} : visage non exploitable.")
        return _result()


async def test_profil_echoue_tolere(monkeypatch):
    monkeypatch.setattr(engine, "_make", lambda name: FakeAnalyzer(no_face={"left"}))
    run = await engine.run_analysis(PHOTOS, mode="facepp")
    assert "left" not in run.results
    assert len(run.results) == 3
    assert "visage non exploitable" in run.photo_status["left"]
    assert run.photo_status["front"] == "ok"


async def test_front_echoue_erreur(monkeypatch):
    monkeypatch.setattr(engine, "_make", lambda name: FakeAnalyzer(no_face={"front"}))
    with pytest.raises(FrontPhotoFailedError):
        await engine.run_analysis(PHOTOS, mode="facepp")


async def test_auto_replie_sur_le_second_moteur(monkeypatch):
    def make(name: str):
        if name == "facepp":
            return FakeAnalyzer(fatal=FaceppQuotaError("quota épuisé"))
        return FakeAnalyzer()

    monkeypatch.setattr(engine, "_make", make)
    run = await engine.run_analysis(PHOTOS, mode="auto")
    assert run.engine == "fake"
    assert len(run.results) == 4


async def test_facepp_seul_remonte_le_quota(monkeypatch):
    monkeypatch.setattr(
        engine, "_make", lambda name: FakeAnalyzer(fatal=FaceppQuotaError("quota"))
    )
    with pytest.raises(FaceppQuotaError):
        await engine.run_analysis(PHOTOS, mode="facepp")
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_engine.py -v`
Expected: FAIL — `ImportError` (module `app.skin.engine` absent)

- [ ] **Step 3: Implémenter**

`backend/app/skin/engine.py` :

```python
"""Façade des moteurs : sélection ANALYSIS_ENGINE (facepp | local | auto).

`auto` essaie Face++ puis se replie sur le moteur local si Face++ est
indisponible (quota, clés, réseau). Défaut Phase 1 : `facepp` — le repli
local ne sait noter que rougeurs + type de peau tant que les poids YOLO ne
sont pas entraînés.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

from .analyzer import (
    EngineUnavailableError,
    FrontPhotoFailedError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)
from .facepp import FaceppAnalyzer

FRONT_KEY = "front"

_MODES = {"facepp": ["facepp"], "local": ["local"], "auto": ["facepp", "local"]}


@dataclass
class EngineRunResult:
    """Résultats par photo + statut par photo + moteur effectivement utilisé."""

    results: dict[str, SkinPhotoResult]
    photo_status: dict[str, str]  # "ok" ou message FR d'échec
    engine: str


def _make(name: str) -> SkinAnalyzer:
    if name == "facepp":
        return FaceppAnalyzer()
    if name == "local":
        try:
            from .local import LocalAnalyzer  # import paresseux (deps Phase 2)
        except ImportError as exc:
            raise EngineUnavailableError(
                "Moteur local indisponible (installer requirements-phase2.txt)."
            ) from exc
        return LocalAnalyzer()
    raise EngineUnavailableError(f"Moteur inconnu : {name}")


async def _run_with(
    analyzer: SkinAnalyzer, photos: dict[str, bytes]
) -> EngineRunResult:
    """Analyse chaque photo ; seule l'échec de la photo de face est bloquant."""
    results: dict[str, SkinPhotoResult] = {}
    status: dict[str, str] = {}
    for name, raw in photos.items():
        try:
            results[name] = await analyzer.analyze_photo(raw)
            status[name] = "ok"
        except NoFaceError as exc:
            if name == FRONT_KEY:
                raise FrontPhotoFailedError(exc.message_fr) from exc
            status[name] = exc.message_fr
    if FRONT_KEY not in results:
        raise FrontPhotoFailedError("front : photo de face manquante.")
    return EngineRunResult(results=results, photo_status=status, engine=analyzer.name)


async def run_analysis(
    photos: dict[str, bytes], mode: str | None = None
) -> EngineRunResult:
    """Point d'entrée du module : applique ANALYSIS_ENGINE et le repli éventuel."""
    mode = mode or os.getenv("ANALYSIS_ENGINE", "facepp")
    if mode not in _MODES:
        raise EngineUnavailableError(f"ANALYSIS_ENGINE invalide : {mode}")
    last_error: EngineUnavailableError | None = None
    for engine_name in _MODES[mode]:
        try:
            return await _run_with(_make(engine_name), photos)
        except EngineUnavailableError as exc:
            last_error = exc
    assert last_error is not None
    raise last_error
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_engine.py -v`
Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/engine.py backend/tests/test_engine.py
git commit -m "feat(backend): façade moteur ANALYSIS_ENGINE avec repli auto"
```

---

### Task 9: Schémas Pydantic + endpoint POST /v1/skin/analyze

**Files:**
- Create: `backend/app/skin/schemas.py`
- Create: `backend/app/skin/router.py`
- Modify: `backend/app/main.py` (inclure le router)
- Test: `backend/tests/test_skin_endpoint.py`

**Interfaces:**
- Consumes: `engine.run_analysis` + `EngineRunResult` (Task 8), `aggregate` (Task 5), `quality.validate_photo`/`PhotoQualityError` (Task 4), `fetch_mappings`/`fetch_products`/`build_recommendations` (Task 7), modèles Task 6, `labels` Task 1, `auth.get_current_pharmacy`, `db.get_db`.
- Produces: `POST /v1/skin/analyze` (multipart `front,left,right,closeup` + form `client_id` optionnel) -> `SkinAnalyzeResponse{analysis_id, skin_type, conditions[], recommendations[], disclaimer_fr}`.

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_skin_endpoint.py` :

```python
"""Tests de POST /v1/skin/analyze (TestClient, moteur et qualité mockés, sqlite)."""
import io

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import auth as auth_module
from app.db import Base, get_db
from app.main import app
from app.models import ConditionProductMap, Client, Pharmacy, SkinAnalysis, VisageProduct
from app.skin.analyzer import CONDITION_CODES, FaceppQuotaError, SkinPhotoResult
from app.skin.engine import EngineRunResult
from app.skin.quality import PhotoQualityError

ALL_OK = {name: "ok" for name in ["front", "left", "right", "closeup"]}


def _photo_result() -> SkinPhotoResult:
    scores = {c: 5 for c in CONDITION_CODES}
    scores["acne"] = 62
    return SkinPhotoResult(scores=scores, skin_type="oily", zones={"acne": ["chin"]})


def _files():
    return {
        name: (f"{name}.jpg", io.BytesIO(b"fake-jpeg"), "image/jpeg")
        for name in ["front", "left", "right", "closeup"]
    }


@pytest.fixture()
def api(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)

    session = Session()
    pharmacy = Pharmacy(nom="Test", email="t@t.tn", password_hash="x")
    session.add(pharmacy)
    session.add_all([
        VisageProduct(id=1, name="Gel anti-acné", brand="A", price=25.5,
                      sub="soins-peau-grasse-mixte-acne", in_stock=True, active=True),
        VisageProduct(id=2, name="Crème anti-rides", brand="B", price=30.0,
                      sub="soins-anti-age-rides", in_stock=True, active=True),
    ])
    session.commit()
    session.add_all([
        ConditionProductMap(condition_code="acne", product_id=1, priority=10),
        ConditionProductMap(condition_code="wrinkles", product_id=2, priority=10),
    ])
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

    monkeypatch.setattr("app.skin.quality.validate_photo", lambda raw, name: None)

    async def fake_run(photos, mode=None):
        return EngineRunResult(
            results={"front": _photo_result()}, photo_status=ALL_OK, engine="facepp"
        )

    monkeypatch.setattr("app.skin.engine.run_analysis", fake_run)

    yield TestClient(app), Session
    app.dependency_overrides.clear()


def test_analyse_ok(api):
    client, Session = api
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["skin_type"] == "oily"
    assert body["disclaimer_fr"].endswith("avis dermatologique.")
    assert body["conditions"][0]["code"] == "acne"
    assert body["conditions"][0]["severity"] == "severe"
    assert body["conditions"][0]["zones"] == ["chin"]
    assert len(body["conditions"]) == 7  # toutes les conditions, triées par score
    ids = [r["product_id"] for r in body["recommendations"]]
    assert 1 in ids and 2 not in ids  # rides à 5 -> sous le seuil
    assert "acné" in body["recommendations"][0]["reason_fr"]

    s = Session()
    saved = s.query(SkinAnalysis).one()
    assert saved.skin_type == "oily"
    assert saved.results_json["engine"] == "facepp"
    s.close()


def test_photo_floue_422(api, monkeypatch):
    client, _ = api

    def reject(raw, name):
        raise PhotoQualityError(f"{name} : photo floue.")

    monkeypatch.setattr("app.skin.quality.validate_photo", reject)
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 422
    assert "floue" in res.json()["detail"]


def test_quota_502(api, monkeypatch):
    client, _ = api

    async def fail(photos, mode=None):
        raise FaceppQuotaError("Service d'analyse temporairement indisponible (quota Face++).")

    monkeypatch.setattr("app.skin.engine.run_analysis", fail)
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 502
    assert "quota" in res.json()["detail"]


def test_client_autre_pharmacie_404(api):
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

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(intrus_id)}
    )
    assert res.status_code == 404


def test_client_de_la_pharmacie_rattache(api):
    client, Session = api
    s = Session()
    mien = Client(pharmacy_id=1, prenom="A", nom="B", telephone="2")
    s.add(mien)
    s.commit()
    mien_id = mien.id
    s.close()

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(mien_id)}
    )
    assert res.status_code == 200
    s = Session()
    assert s.query(SkinAnalysis).one().client_id == mien_id
    s.close()
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py -v`
Expected: FAIL — 404 sur `/v1/skin/analyze` (route absente) ou `ImportError` (schemas absents)

- [ ] **Step 3: Implémenter les schémas**

`backend/app/skin/schemas.py` :

```python
"""Schémas Pydantic v2 du contrat /v1/skin/analyze."""
from __future__ import annotations

from pydantic import BaseModel, Field


class ConditionOut(BaseModel):
    code: str
    label_fr: str
    score: int = Field(ge=0, le=100)
    severity: str  # mild | moderate | severe
    zones: list[str] = []


class RecommendationOut(BaseModel):
    product_id: int
    name: str
    brand: str | None = None
    price: float | None = None
    image_url: str | None = None
    reason_fr: str
    matched_conditions: list[str] = []


class SkinAnalyzeResponse(BaseModel):
    analysis_id: int
    skin_type: str
    conditions: list[ConditionOut]
    recommendations: list[RecommendationOut]
    disclaimer_fr: str
```

- [ ] **Step 4: Implémenter le router**

`backend/app/skin/router.py` :

```python
"""Route POST /v1/skin/analyze — analyse de peau 4 photos + recommandations.

Conformité RGPD : les photos sont traitées en mémoire et jamais persistées ;
seuls les résultats JSON sont stockés dans skin_analyses.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .. import auth as auth_module
from ..db import get_db
from ..models import Client, Pharmacy, SkinAnalysis
from . import engine as engine_mod
from . import quality
from .aggregate import aggregate
from .analyzer import (
    EngineUnavailableError,
    FaceppQuotaError,
    FrontPhotoFailedError,
)
from .labels import DISCLAIMER_FR, LABELS_FR, severity
from .recommend import build_recommendations, fetch_mappings, fetch_products
from .schemas import ConditionOut, RecommendationOut, SkinAnalyzeResponse

logger = logging.getLogger("skin")

router = APIRouter(tags=["skin"])

MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@router.post("/v1/skin/analyze", response_model=SkinAnalyzeResponse)
async def analyze_skin(
    front: UploadFile = File(...),
    left: UploadFile = File(...),
    right: UploadFile = File(...),
    closeup: UploadFile = File(...),
    client_id: int | None = Form(default=None),
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> SkinAnalyzeResponse:
    """Analyse les 4 photos et renvoie conditions + recommandations produits."""
    if client_id is not None:
        client = db.get(Client, client_id)
        if client is None or client.pharmacy_id != pharmacy.id:
            raise HTTPException(status_code=404, detail="Client introuvable")

    photos: dict[str, bytes] = {}
    uploads = {"front": front, "left": left, "right": right, "closeup": closeup}
    for name, upload in uploads.items():
        if upload.content_type not in ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status_code=415,
                detail=f"{name} : type non supporté ({upload.content_type}).",
            )
        raw = await upload.read()
        if not raw:
            raise HTTPException(status_code=400, detail=f"{name} : image vide.")
        if len(raw) > MAX_IMAGE_BYTES:
            raise HTTPException(
                status_code=413, detail=f"{name} : image trop volumineuse (max 10 Mo)."
            )
        try:
            quality.validate_photo(raw, name)
        except quality.PhotoQualityError as exc:
            raise HTTPException(status_code=422, detail=exc.message_fr) from exc
        photos[name] = raw

    try:
        run = await engine_mod.run_analysis(photos)
    except FrontPhotoFailedError as exc:
        raise HTTPException(status_code=422, detail=exc.message_fr) from exc
    except FaceppQuotaError as exc:
        raise HTTPException(status_code=502, detail=exc.message_fr) from exc
    except EngineUnavailableError as exc:
        raise HTTPException(status_code=502, detail=exc.message_fr) from exc

    scores, skin_type, zones = aggregate(run.results)

    mappings = fetch_mappings(db, list(scores) + [f"skin_type_{skin_type}"])
    products = fetch_products(db, [m["product_id"] for m in mappings])
    recommendations = build_recommendations(scores, skin_type, mappings, products)

    analysis = SkinAnalysis(
        pharmacy_id=pharmacy.id,
        client_id=client_id,
        skin_type=skin_type,
        results_json={
            "scores": scores,
            "zones": zones,
            "engine": run.engine,
            "photo_status": run.photo_status,
        },
    )
    db.add(analysis)
    db.commit()
    db.refresh(analysis)

    conditions = [
        ConditionOut(
            code=code,
            label_fr=LABELS_FR[code],
            score=score,
            severity=severity(score),
            zones=zones.get(code, []),
        )
        for code, score in sorted(scores.items(), key=lambda kv: -kv[1])
    ]
    recs = [
        RecommendationOut(
            product_id=r.product_id,
            name=r.name,
            brand=r.brand,
            price=r.price,
            image_url=r.image_url,
            reason_fr=r.reason_fr,
            matched_conditions=r.matched_conditions,
        )
        for r in recommendations
    ]
    return SkinAnalyzeResponse(
        analysis_id=analysis.id,
        skin_type=skin_type,
        conditions=conditions,
        recommendations=recs,
        disclaimer_fr=DISCLAIMER_FR,
    )
```

Dans `backend/app/main.py`, après la création de `app` et du middleware CORS, ajouter :

```python
from .skin.router import router as skin_router

app.include_router(skin_router)
```

(Placer l'import en haut du fichier avec les autres imports relatifs.)

- [ ] **Step 5: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_skin_endpoint.py -v`
Expected: 5 PASS

Run: `cd backend && python -m pytest tests -v`
Expected: tous les tests passent (aucune régression)

- [ ] **Step 6: Commit**

```bash
git add backend/app/skin/schemas.py backend/app/skin/router.py backend/app/main.py backend/tests/test_skin_endpoint.py
git commit -m "feat(backend): endpoint POST /v1/skin/analyze (JWT, 4 photos, recommandations)"
```

---

### Task 10: Scaffold LocalAnalyzer (Phase 2)

**Files:**
- Create: `backend/app/skin/local.py`
- Create: `backend/requirements-phase2.txt`
- Test: `backend/tests/test_local.py`

**Interfaces:**
- Consumes: `SkinAnalyzer`, `SkinPhotoResult`, `CONDITION_CODES`, `EngineUnavailableError`, `NoFaceError` (Task 1).
- Produces: `LocalAnalyzer` (name="local") ; fonctions pures testables sans deps lourdes : `redness_score(img_bgr, mask=None) -> int`, `oiliness_proxy(gray_values) -> float`, `combine_skin_type(base_type, t_zone_oiliness, cheek_oiliness) -> str` ; `CLASS_TO_CONDITION` (ordre des classes YOLO, consommé par `train/train_yolo.py`).

- [ ] **Step 1: Écrire les tests qui échouent**

`backend/tests/test_local.py` :

```python
"""Tests des parties pures du moteur local (sans mediapipe/transformers)."""
import numpy as np

from app.skin.local import combine_skin_type, oiliness_proxy, redness_score


def test_rouge_pur_score_maximal():
    img = np.zeros((100, 100, 3), np.uint8)
    img[:, :, 2] = 255  # BGR : canal rouge saturé
    assert redness_score(img) == 100


def test_gris_neutre_score_nul():
    img = np.full((100, 100, 3), 128, np.uint8)
    assert redness_score(img) <= 5


def test_redness_respecte_le_masque():
    img = np.full((100, 100, 3), 128, np.uint8)
    img[:50, :, 2] = 255  # moitié haute rouge
    mask_bas = np.zeros((100, 100), np.uint8)
    mask_bas[50:, :] = 255
    assert redness_score(img, mask_bas) <= 5
    mask_haut = np.zeros((100, 100), np.uint8)
    mask_haut[:50, :] = 255
    assert redness_score(img, mask_haut) >= 60


def test_oiliness_proxy():
    values = np.zeros(100, np.uint8)
    values[:10] = 255  # 10 % de pixels spéculaires
    assert abs(oiliness_proxy(values) - 0.10) < 1e-6
    assert oiliness_proxy(np.array([], np.uint8)) == 0.0


def test_combination_si_tzone_brillante_et_joues_mates():
    assert combine_skin_type("normal", 0.20, 0.00) == "combination"
    assert combine_skin_type("dry", 0.00, 0.00) == "dry"
    # joues brillantes aussi -> pas mixte, on garde le type de base
    assert combine_skin_type("oily", 0.09, 0.05) == "oily"
```

- [ ] **Step 2: Vérifier l'échec**

Run: `cd backend && python -m pytest tests/test_local.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.skin.local'`

- [ ] **Step 3: Implémenter**

`backend/requirements-phase2.txt` :

```text
# Dépendances lourdes du moteur local (Phase 2) — installer séparément :
#     pip install -r requirements-phase2.txt
mediapipe>=0.10
transformers>=4.40
torch>=2.2
pillow>=10
ultralytics>=8.2
```

`backend/app/skin/local.py` :

```python
"""Moteur local (Phase 2) — zones MediaPipe, rougeurs OpenCV, type de peau HF.

État actuel :
- rougeurs (canal a* CIELAB sur joues/nez) : fonctionnel ;
- type de peau : HF `dima806/skin_types_image_detection` + logique T-zone
  pour détecter `combination` ;
- autres conditions : hooks YOLOv8-ONNX, actifs uniquement si
  SKIN_YOLO_MODEL_PATH pointe vers un modèle exporté (train/train_yolo.py) ;
  sinon leurs scores restent à 0.

Les dépendances lourdes (mediapipe, transformers, torch) sont importées
paresseusement : requirements-phase2.txt.
"""
from __future__ import annotations

import os

import cv2
import numpy as np

from .analyzer import (
    CONDITION_CODES,
    EngineUnavailableError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)

# Ordre des classes du modèle YOLO (doit correspondre au data.yaml d'entraînement).
CLASS_TO_CONDITION = {
    0: "acne",
    1: "blackheads",
    2: "dark_spots",
    3: "enlarged_pores",
    4: "wrinkles",
}

# Indices de landmarks FaceMesh (468 points) approximant chaque zone.
ZONE_LANDMARKS = {
    "forehead": [10, 67, 69, 104, 108, 151, 297, 299, 333, 337],
    "nose": [1, 4, 5, 6, 19, 44, 45, 51, 274, 275, 281],
    "left_cheek": [50, 101, 118, 123, 187, 205, 207],
    "right_cheek": [280, 330, 347, 352, 411, 425, 427],
    "chin": [18, 32, 148, 152, 175, 199, 262, 377],
}

# Seuils de la logique « peau mixte » (fractions de pixels spéculaires).
T_ZONE_OILY_MIN = 0.08
CHEEK_MATTE_MAX = 0.02


def redness_score(img_bgr: np.ndarray, mask: np.ndarray | None = None) -> int:
    """Rougeur 0-100 depuis le canal a* CIELAB (128 = neutre en OpenCV)."""
    lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB)
    a_channel = lab[:, :, 1].astype(np.float32)
    if mask is not None:
        values = a_channel[mask > 0]
        if values.size == 0:
            values = a_channel.reshape(-1)
    else:
        values = a_channel.reshape(-1)
    mean_a = float(values.mean())
    # ~132 = teint neutre ; chaque point au-dessus compte pour 6 points de score.
    return int(np.clip((mean_a - 132.0) * 6.0, 0.0, 100.0))


def oiliness_proxy(gray_values: np.ndarray) -> float:
    """Fraction de pixels spéculaires (>230) — proxy simple de brillance/séborrhée."""
    if gray_values.size == 0:
        return 0.0
    return float((gray_values > 230).mean())


def combine_skin_type(
    base_type: str, t_zone_oiliness: float, cheek_oiliness: float
) -> str:
    """`combination` si la T-zone brille alors que les joues sont mates."""
    if t_zone_oiliness >= T_ZONE_OILY_MIN and cheek_oiliness <= CHEEK_MATTE_MAX:
        return "combination"
    return base_type


class LocalAnalyzer(SkinAnalyzer):
    """Moteur local gratuit — remplacera Face++ une fois les poids YOLO entraînés."""

    name = "local"

    def __init__(self):
        self._face_mesh = None
        self._skin_type_pipe = None
        self._yolo_session = None

    # ---------- chargements paresseux ----------

    def _get_face_mesh(self):
        if self._face_mesh is None:
            try:
                import mediapipe as mp
            except ImportError as exc:
                raise EngineUnavailableError(
                    "Moteur local : installer requirements-phase2.txt (mediapipe)."
                ) from exc
            self._face_mesh = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True, max_num_faces=1, refine_landmarks=False
            )
        return self._face_mesh

    def _get_skin_type_pipe(self):
        if self._skin_type_pipe is None:
            try:
                from transformers import pipeline
            except ImportError as exc:
                raise EngineUnavailableError(
                    "Moteur local : installer requirements-phase2.txt (transformers)."
                ) from exc
            self._skin_type_pipe = pipeline(
                "image-classification", model="dima806/skin_types_image_detection"
            )
        return self._skin_type_pipe

    # ---------- étapes d'analyse ----------

    def _landmarks(self, img_bgr: np.ndarray) -> np.ndarray:
        mesh = self._get_face_mesh()
        result = mesh.process(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
        if not result.multi_face_landmarks:
            raise NoFaceError("aucun visage détecté (moteur local).")
        height, width = img_bgr.shape[:2]
        landmarks = result.multi_face_landmarks[0].landmark
        return np.array(
            [[p.x * width, p.y * height] for p in landmarks], dtype=np.int32
        )

    def _zone_mask(
        self, shape: tuple, points: np.ndarray, indices: list[int]
    ) -> np.ndarray:
        mask = np.zeros(shape[:2], np.uint8)
        hull = cv2.convexHull(points[indices])
        cv2.fillConvexPoly(mask, hull, 255)
        return mask

    def _classify_skin_type(self, img_bgr: np.ndarray) -> str:
        from PIL import Image

        pipe = self._get_skin_type_pipe()
        rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        predictions = pipe(Image.fromarray(rgb))
        label = max(predictions, key=lambda p: p["score"])["label"].lower()
        if "dry" in label:
            return "dry"
        if "oily" in label:
            return "oily"
        return "normal"

    def _yolo_scores(self, img_bgr: np.ndarray) -> dict[str, int]:
        """Inférence ONNX (export ultralytics nms=True). {} si pas de modèle."""
        model_path = os.getenv("SKIN_YOLO_MODEL_PATH", "").strip()
        if not model_path or not os.path.exists(model_path):
            return {}
        import onnxruntime as ort

        if self._yolo_session is None:
            self._yolo_session = ort.InferenceSession(
                model_path, providers=["CPUExecutionProvider"]
            )
        model_input = self._yolo_session.get_inputs()[0]
        size = model_input.shape[2] if isinstance(model_input.shape[2], int) else 640
        resized = cv2.resize(img_bgr, (size, size))
        blob = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        blob = blob.transpose(2, 0, 1)[None]
        detections = self._yolo_session.run(None, {model_input.name: blob})[0][0]
        best: dict[str, float] = {}
        for det in detections:  # (x1, y1, x2, y2, conf, cls)
            confidence, cls = float(det[4]), int(det[5])
            condition = CLASS_TO_CONDITION.get(cls)
            if condition and confidence > best.get(condition, 0.0):
                best[condition] = confidence
        return {c: round(v * 100) for c, v in best.items()}

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            raise NoFaceError("image illisible (moteur local).")

        points = self._landmarks(img)
        masks = {
            zone: self._zone_mask(img.shape, points, indices)
            for zone, indices in ZONE_LANDMARKS.items()
        }

        scores = {condition: 0 for condition in CONDITION_CODES}
        cheeks_nose = cv2.bitwise_or(
            cv2.bitwise_or(masks["left_cheek"], masks["right_cheek"]), masks["nose"]
        )
        scores["redness"] = redness_score(img, cheeks_nose)
        scores.update(self._yolo_scores(img))

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        t_zone = cv2.bitwise_or(masks["forehead"], masks["nose"])
        cheeks = cv2.bitwise_or(masks["left_cheek"], masks["right_cheek"])
        base_type = self._classify_skin_type(img)
        skin_type = combine_skin_type(
            base_type,
            oiliness_proxy(gray[t_zone > 0]),
            oiliness_proxy(gray[cheeks > 0]),
        )

        zones: dict[str, list[str]] = {}
        if scores["redness"] >= 30:
            zones["redness"] = ["left_cheek", "right_cheek", "nose"]
        return SkinPhotoResult(scores=scores, skin_type=skin_type, zones=zones)
```

- [ ] **Step 4: Vérifier le succès**

Run: `cd backend && python -m pytest tests/test_local.py -v`
Expected: 5 PASS

Run: `cd backend && python -m pytest tests -v`
Expected: tous les tests passent

- [ ] **Step 5: Commit**

```bash
git add backend/app/skin/local.py backend/requirements-phase2.txt backend/tests/test_local.py
git commit -m "feat(backend): scaffold moteur local Phase 2 (rougeurs, type de peau, hooks YOLO)"
```

---

### Task 11: Script d'entraînement YOLOv8 + documentation README

**Files:**
- Create: `backend/train/train_yolo.py`
- Modify: `backend/README.md` (ajouter une section à la fin)

**Interfaces:**
- Consumes: `CLASS_TO_CONDITION` (Task 10 — l'ordre des classes doit correspondre).
- Produces: script CLI Colab-ready ; documentation d'installation/exploitation.

- [ ] **Step 1: Script d'entraînement**

`backend/train/train_yolo.py` :

```python
"""Entraînement YOLOv8 pour la détection de conditions de peau (Phase 2).

Conçu pour Google Colab (GPU T4 gratuit) :

    !pip install ultralytics roboflow
    !python train_yolo.py --roboflow-api-key $RF_KEY \
        --workspace <workspace> --project <project> --version 1 --epochs 60

IMPORTANT — ordre des classes du dataset (data.yaml) : il doit suivre
CLASS_TO_CONDITION de app/skin/local.py :
    0: acne, 1: blackheads, 2: dark_spots, 3: enlarged_pores, 4: wrinkles

Datasets libres : https://universe.roboflow.com (rechercher « acne »,
« blackheads », « wrinkles », « dark spots », « pores ») ; fusionner les
exports dans un seul projet Roboflow à 5 classes avant l'entraînement.
"""
from __future__ import annotations

import argparse


def download_from_roboflow(
    api_key: str, workspace: str, project: str, version: int
) -> str:
    """Télécharge le dataset Roboflow au format YOLOv8, renvoie le data.yaml."""
    from roboflow import Roboflow

    dataset = (
        Roboflow(api_key=api_key)
        .workspace(workspace)
        .project(project)
        .version(version)
        .download("yolov8")
    )
    return f"{dataset.location}/data.yaml"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Entraînement YOLOv8 conditions de peau (Colab)"
    )
    parser.add_argument("--data", help="Chemin d'un data.yaml local (sinon Roboflow)")
    parser.add_argument("--roboflow-api-key")
    parser.add_argument("--workspace")
    parser.add_argument("--project")
    parser.add_argument("--version", type=int, default=1)
    parser.add_argument("--model", default="yolov8n.pt")
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--imgsz", type=int, default=640)
    args = parser.parse_args()

    data = args.data
    if not data:
        if not (args.roboflow_api_key and args.workspace and args.project):
            parser.error(
                "--data OU (--roboflow-api-key --workspace --project) requis"
            )
        data = download_from_roboflow(
            args.roboflow_api_key, args.workspace, args.project, args.version
        )

    from ultralytics import YOLO

    model = YOLO(args.model)
    results = model.train(data=data, epochs=args.epochs, imgsz=args.imgsz)
    best = results.save_dir / "weights" / "best.pt"

    # nms=True : sortie (N, 6) attendue par LocalAnalyzer._yolo_scores.
    onnx_path = YOLO(str(best)).export(format="onnx", nms=True, imgsz=args.imgsz)
    print(f"Modèle ONNX exporté : {onnx_path}")
    print("Copier ce fichier sur le serveur puis définir SKIN_YOLO_MODEL_PATH dans .env")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Vérifier la syntaxe**

Run: `cd backend && python -m py_compile train/train_yolo.py && python train/train_yolo.py --help`
Expected: aide affichée sans erreur (les imports lourds sont dans les fonctions)

- [ ] **Step 3: Documenter**

Ajouter à la fin de `backend/README.md` :

````markdown

## Analyse de peau (module `app/skin/`)

`POST /v1/skin/analyze` (JWT pharmacie) reçoit 4 photos (`front`, `left`,
`right`, `closeup`) + `client_id` optionnel et renvoie : type de peau,
7 conditions notées 0–100, recommandations produits et disclaimer médical.
Les photos sont traitées en mémoire et jamais stockées.

### Phase 1 — Face++ (moteur par défaut)

1. Créer un compte gratuit sur <https://console.faceplusplus.com>.
2. Créer une application API → récupérer **API Key** et **API Secret**.
3. Compléter `backend/.env` :

   ```env
   FACEPP_API_KEY=...
   FACEPP_API_SECRET=...
   FACEPP_ENDPOINT=https://api-us.faceplusplus.com/facepp/v1/skinanalyze
   ANALYSIS_ENGINE=facepp      # facepp | local | auto
   SKIN_BLUR_THRESHOLD=60
   SKIN_YOLO_MODEL_PATH=       # Phase 2, vide = hooks YOLO inactifs
   ```

### Recommandations produits

Le mapping condition → produits est dérivé des sous-catégories (`sub`) de
`visage_products` :

```bash
python -m scripts.seed_condition_map
```

Relançable à volonté (idempotent). Ajuster ensuite les priorités directement
dans la table `condition_product_map` si besoin.

### Tests

```bash
pip install -r requirements-dev.txt
python -m pytest tests -v
```

Test manuel (après login pour obtenir un token) :

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@lumina.com","password":"lumina123"}' | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -X POST http://127.0.0.1:8000/v1/skin/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -F front=@face.jpg -F left=@gauche.jpg -F right=@droit.jpg -F closeup=@front.jpg
```

### Phase 2 — moteur local gratuit

```bash
pip install -r requirements-phase2.txt
```

- Rougeurs (OpenCV, CIELAB) et type de peau (HF
  `dima806/skin_types_image_detection` + logique T-zone) fonctionnent sans
  entraînement.
- Conditions (acné, points noirs, taches, pores, rides) : entraîner YOLOv8
  sur Google Colab avec `train/train_yolo.py` (datasets gratuits sur
  <https://universe.roboflow.com> — fusionner en un projet à 5 classes dans
  l'ordre de `CLASS_TO_CONDITION` de `app/skin/local.py`), puis copier
  l'export ONNX sur le serveur et renseigner `SKIN_YOLO_MODEL_PATH`.
- Une fois validé, passer `ANALYSIS_ENGINE=auto` (Face++ avec repli local)
  ou `local`.

> ⚠️ Les résultats (acné, rougeurs/rosacée…) sont une aide cosmétique, pas un
> diagnostic médical : le disclaimer doit rester visible partout où ils sont
> affichés.
````

- [ ] **Step 4: Commit**

```bash
git add backend/train/train_yolo.py backend/README.md
git commit -m "docs(backend): script entraînement YOLOv8 Colab + doc module skin"
```

---

### Task 12: Flutter — modèles + client API skin

**Files:**
- Create: `frontend/lib/models/skin_analysis.dart`
- Create: `frontend/lib/services/skin_api.dart`
- Modify: `frontend/pubspec.yaml` (ajouter flutter_test en dev)
- Test: `frontend/test/skin_analysis_test.dart`

**Interfaces:**
- Consumes: `ApiConfig.baseUrl` (`frontend/lib/services/api_config.dart`).
- Produces: `SkinAnalysisResult`, `SkinCondition`, `ProductRecommendation` (+ `fromJson`) ; `SkinApi({baseUrl, token}).analyze({required File front, left, right, closeup, int? clientId}) -> Future<SkinAnalysisResult>` ; `SkinApiException(message)`.

- [ ] **Step 1: Dépendance de test**

Dans `frontend/pubspec.yaml`, remplacer :

```yaml
dev_dependencies:
  flutter_lints: ^4.0.0
```

par :

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

Puis : `cd frontend && flutter pub get`

- [ ] **Step 2: Écrire le test qui échoue**

`frontend/test/skin_analysis_test.dart` :

```dart
import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SkinAnalysisResult.fromJson parse le contrat complet', () {
    final json = {
      'analysis_id': 123,
      'skin_type': 'combination',
      'conditions': [
        {
          'code': 'acne',
          'label_fr': 'Acné / boutons',
          'score': 62,
          'severity': 'severe',
          'zones': ['chin', 'forehead'],
        },
      ],
      'recommendations': [
        {
          'product_id': 45,
          'name': 'Gel nettoyant',
          'brand': 'Marque',
          'price': 25.5,
          'image_url': null,
          'reason_fr': 'Recommandé pour votre acné marquée.',
          'matched_conditions': ['acne'],
        },
      ],
      'disclaimer_fr':
          'Cette analyse est indicative et ne remplace pas un avis dermatologique.',
    };

    final result = SkinAnalysisResult.fromJson(json);

    expect(result.analysisId, 123);
    expect(result.skinType, 'combination');
    expect(result.conditions.single.labelFr, 'Acné / boutons');
    expect(result.conditions.single.zones, ['chin', 'forehead']);
    expect(result.recommendations.single.productId, 45);
    expect(result.recommendations.single.price, 25.5);
    expect(result.recommendations.single.imageUrl, isNull);
    expect(result.recommendations.single.matchedConditions, ['acne']);
    expect(result.disclaimerFr, contains('dermatologique'));
  });
}
```

- [ ] **Step 3: Vérifier l'échec**

Run: `cd frontend && flutter test test/skin_analysis_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'analyse_faciale'... skin_analysis.dart` (fichier manquant)

- [ ] **Step 4: Implémenter les modèles**

`frontend/lib/models/skin_analysis.dart` :

```dart
/// Modèles du diagnostic de peau renvoyé par `POST /v1/skin/analyze`.
class SkinCondition {
  final String code;
  final String labelFr;
  final int score; // 0-100
  final String severity; // mild | moderate | severe
  final List<String> zones;

  const SkinCondition({
    required this.code,
    required this.labelFr,
    required this.score,
    required this.severity,
    this.zones = const [],
  });

  factory SkinCondition.fromJson(Map<String, dynamic> json) {
    return SkinCondition(
      code: json['code'] as String,
      labelFr: json['label_fr'] as String? ?? json['code'] as String,
      score: (json['score'] as num?)?.toInt() ?? 0,
      severity: json['severity'] as String? ?? 'mild',
      zones: (json['zones'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class ProductRecommendation {
  final int productId;
  final String name;
  final String? brand;
  final double? price;
  final String? imageUrl;
  final String reasonFr;
  final List<String> matchedConditions;

  const ProductRecommendation({
    required this.productId,
    required this.name,
    this.brand,
    this.price,
    this.imageUrl,
    required this.reasonFr,
    this.matchedConditions = const [],
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      productId: (json['product_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      reasonFr: json['reason_fr'] as String? ?? '',
      matchedConditions:
          (json['matched_conditions'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class SkinAnalysisResult {
  final int analysisId;
  final String skinType; // oily | dry | combination | normal
  final List<SkinCondition> conditions;
  final List<ProductRecommendation> recommendations;
  final String disclaimerFr;

  const SkinAnalysisResult({
    required this.analysisId,
    required this.skinType,
    required this.conditions,
    required this.recommendations,
    required this.disclaimerFr,
  });

  factory SkinAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SkinAnalysisResult(
      analysisId: (json['analysis_id'] as num).toInt(),
      skinType: json['skin_type'] as String? ?? 'normal',
      conditions: (json['conditions'] as List? ?? const [])
          .map((c) => SkinCondition.fromJson(c as Map<String, dynamic>))
          .toList(),
      recommendations: (json['recommendations'] as List? ?? const [])
          .map((r) => ProductRecommendation.fromJson(r as Map<String, dynamic>))
          .toList(),
      disclaimerFr: json['disclaimer_fr'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 5: Implémenter le client API**

`frontend/lib/services/skin_api.dart` :

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/skin_analysis.dart';
import 'api_config.dart';

/// Erreur d'analyse porteuse d'un message prêt à afficher.
class SkinApiException implements Exception {
  final String message;
  const SkinApiException(this.message);

  @override
  String toString() => message;
}

/// Client HTTP de `POST /v1/skin/analyze` (4 photos, JWT pharmacie).
class SkinApi {
  final String baseUrl;
  final String? token;

  SkinApi({this.baseUrl = ApiConfig.baseUrl, this.token});

  Future<SkinAnalysisResult> analyze({
    required File front,
    required File left,
    required File right,
    required File closeup,
    int? clientId,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/skin/analyze');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    // contentType explicite : le backend rejette application/octet-stream.
    final jpeg = MediaType('image', 'jpeg');
    request.files.add(
        await http.MultipartFile.fromPath('front', front.path, contentType: jpeg));
    request.files.add(
        await http.MultipartFile.fromPath('left', left.path, contentType: jpeg));
    request.files.add(
        await http.MultipartFile.fromPath('right', right.path, contentType: jpeg));
    request.files.add(await http.MultipartFile.fromPath('closeup', closeup.path,
        contentType: jpeg));
    if (clientId != null) {
      request.fields['client_id'] = '$clientId';
    }

    // 4 photos + API externe : délai volontairement long.
    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      String message = 'Erreur serveur (${response.statusCode}).';
      try {
        final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
        if (detail is String && detail.isNotEmpty) message = detail;
      } catch (_) {
        // corps non JSON : on garde le message générique
      }
      throw SkinApiException(message);
    }
    return SkinAnalysisResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}
```

- [ ] **Step 6: Vérifier le succès**

Run: `cd frontend && flutter test test/skin_analysis_test.dart && flutter analyze lib/models/skin_analysis.dart lib/services/skin_api.dart`
Expected: test PASS, analyze sans issue

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/models/skin_analysis.dart frontend/lib/services/skin_api.dart frontend/pubspec.yaml frontend/test/skin_analysis_test.dart
git commit -m "feat(frontend): modèles + client API analyse de peau"
```

---

### Task 13: Flutter — écran résultat SkinResultScreen

**Files:**
- Create: `frontend/lib/screens/skin_result_screen.dart`

**Interfaces:**
- Consumes: `SkinAnalysisResult`, `SkinCondition`, `ProductRecommendation` (Task 12) ; widgets/thème existants : `AppHeader(title:)`, `CustomButton(label, icon, onPressed, ghost)`, `CustomCard(child:)`, `AppColors.*`, `AppSpacing.*`.
- Produces: `SkinResultScreen({required SkinAnalysisResult result, required VoidCallback onRetry})`.

- [ ] **Step 1: Implémenter l'écran**

`frontend/lib/screens/skin_result_screen.dart` :

```dart
import 'package:flutter/material.dart';

import '../models/skin_analysis.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_header.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_card.dart';

/// Résultat de l'analyse de peau : type, conditions, produits, disclaimer.
class SkinResultScreen extends StatelessWidget {
  final SkinAnalysisResult result;
  final VoidCallback onRetry;

  const SkinResultScreen({
    super.key,
    required this.result,
    required this.onRetry,
  });

  static const _skinTypeLabels = {
    'oily': 'Grasse',
    'dry': 'Sèche',
    'combination': 'Mixte',
    'normal': 'Normale',
  };

  static const _severityLabels = {
    'mild': 'Faible',
    'moderate': 'Modérée',
    'severe': 'Marquée',
  };

  Color _severityColor(int score) {
    if (score >= 60) return AppColors.negative;
    if (score >= 30) return Colors.orange;
    return AppColors.positive;
  }

  @override
  Widget build(BuildContext context) {
    // On ne met en avant que les conditions au-dessus du seuil de recommandation.
    final visibles = result.conditions.where((c) => c.score >= 30).toList();

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
                  _buildSkinTypeCard(context),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Conditions détectées',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (visibles.isEmpty)
                    const CustomCard(
                      child: Text('Aucune condition marquée détectée.'),
                    )
                  else
                    ...visibles.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildConditionTile(context, c),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Produits recommandés',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (result.recommendations.isEmpty)
                    const CustomCard(
                      child: Text('Aucun produit correspondant en stock.'),
                    )
                  else
                    ...result.recommendations.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _buildRecommendationTile(context, r),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildDisclaimer(context),
                  const SizedBox(height: AppSpacing.lg),
                  CustomButton(
                    label: 'Refaire la capture',
                    icon: Icons.refresh,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkinTypeCard(BuildContext context) {
    final label = _skinTypeLabels[result.skinType] ?? result.skinType;
    return CustomCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.water_drop_outlined,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type de peau',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionTile(BuildContext context, SkinCondition condition) {
    final color = _severityColor(condition.score);
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  condition.labelFr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _severityLabels[condition.severity] ?? condition.severity,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: condition.score / 100,
              minHeight: 8,
              color: color,
              backgroundColor: AppColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationTile(
      BuildContext context, ProductRecommendation reco) {
    return CustomCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SizedBox(
              width: 56,
              height: 56,
              child: reco.imageUrl == null
                  ? Container(
                      color: AppColors.primaryLight,
                      child: const Icon(Icons.spa_outlined,
                          color: AppColors.primary),
                    )
                  : Image.network(
                      reco.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primaryLight,
                        child: const Icon(Icons.spa_outlined,
                            color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reco.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reco.brand != null)
                  Text(reco.brand!,
                      style: Theme.of(context).textTheme.bodySmall),
                if (reco.price != null)
                  Text(
                    '${reco.price!.toStringAsFixed(2)} DT',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  reco.reasonFr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              result.disclaimerFr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Vérifier**

Run: `cd frontend && flutter analyze lib/screens/skin_result_screen.dart`
Expected: No issues found

Note : si `AppSpacing.radiusMd` n'existe pas dans `frontend/lib/theme/app_spacing.dart`, vérifier le nom exact utilisé par `result_screen.dart` (il utilise `AppSpacing.radiusMd`) et s'aligner dessus.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/screens/skin_result_screen.dart
git commit -m "feat(frontend): écran résultat diagnostic de peau"
```

---

### Task 14: Flutter — câblage du flux de capture (4 photos)

**Files:**
- Modify: `frontend/lib/screens/analyzing_screen.dart` (rendre générique)
- Modify: `frontend/lib/capture/capture_flow.dart` (ConsumerWidget + 4 photos)

**Interfaces:**
- Consumes: `SkinApi` (Task 12), `SkinResultScreen` (Task 13), `authProvider` (`frontend/lib/providers/auth_provider.dart`), `sessionFlowProvider` (`frontend/lib/providers/session_flow_provider.dart`, champ `state.client?.id`), `CapturePose`/`CapturedShot` existants.
- Produces: flux complet capture → validation → `/v1/skin/analyze` → `SkinResultScreen`.

- [ ] **Step 1: Généraliser AnalyzingScreen**

Dans `frontend/lib/screens/analyzing_screen.dart` :

1. Supprimer la ligne `import '../services/analysis_api.dart';`
2. Remplacer la déclaration du widget :

```dart
/// Écran affiché pendant l'appel au backend : anneau de progression
/// indéterminé + liste d'étapes (thème clair Lumina). Possède l'appel API.
/// Générique : `T` est le type de résultat renvoyé par `analyze`.
class AnalyzingScreen<T> extends StatefulWidget {
  final Future<T> Function() analyze;
  final void Function(T result) onResult;
  final VoidCallback onRetry;

  const AnalyzingScreen({
    super.key,
    required this.analyze,
    required this.onResult,
    required this.onRetry,
  });

  @override
  State<AnalyzingScreen<T>> createState() => _AnalyzingScreenState<T>();
}

class _AnalyzingScreenState<T> extends State<AnalyzingScreen<T>> {
```

(le corps de `_AnalyzingScreenState` ne change pas — `widget.analyze()` et `widget.onResult(result)` restent identiques)

3. Actualiser les textes dans `_buildProgress` :
   - `'Détection du visage…'` → `'Analyse de votre peau…'`
   - `"Nous analysons la photo pour estimer l'âge et le sexe."` → `"Nous analysons vos 4 photos pour évaluer votre peau."`
   - Les 3 étapes : `'Photos importées'` (done), `'Analyse de la peau'` (active), `'Recommandations'` (pending).

- [ ] **Step 2: Réécrire CaptureFlow**

Remplacer intégralement `frontend/lib/capture/capture_flow.dart` par :

```dart
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skin_analysis.dart';
import '../providers/auth_provider.dart';
import '../providers/session_flow_provider.dart';
import '../screens/analyzing_screen.dart';
import '../screens/skin_result_screen.dart';
import '../services/skin_api.dart';
import 'capture_pose.dart';
import 'photo_validation_screen.dart';
import 'pose_capture_screen.dart';

/// Orchestre le flux : capture des 4 vues -> validation -> analyse peau -> résultat.
class CaptureFlow extends ConsumerWidget {
  final List<CameraDescription> cameras;

  const CaptureFlow({super.key, required this.cameras});

  void _onCaptureCompleted(
      BuildContext context, WidgetRef ref, List<CapturedShot> shots) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoValidationScreen(
          cameras: cameras,
          shots: shots,
          onConfirmed: (confirmed) => _startAnalysis(context, ref, confirmed),
        ),
      ),
    );
  }

  void _startAnalysis(
      BuildContext context, WidgetRef ref, List<CapturedShot> shots) {
    File? fileFor(CapturePose pose) {
      for (final shot in shots) {
        if (shot.pose == pose) return File(shot.path);
      }
      return null;
    }

    // Correspondance poses locales -> champs du backend :
    // face -> front, profils -> left/right, gros plan du front -> closeup.
    final front = fileFor(CapturePose.face);
    final left = fileFor(CapturePose.profilGauche);
    final right = fileFor(CapturePose.profilDroit);
    final closeup = fileFor(CapturePose.front);
    if (front == null || left == null || right == null || closeup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il manque une photo — refaites la capture.')),
      );
      return;
    }

    final api = SkinApi(token: ref.read(authProvider).session?.token);
    final clientId = ref.read(sessionFlowProvider).client?.id;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen<SkinAnalysisResult>(
          analyze: () => api.analyze(
            front: front,
            left: left,
            right: right,
            closeup: closeup,
            clientId: clientId,
          ),
          onResult: (result) => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SkinResultScreen(
                result: result,
                onRetry: () => Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ),
          ),
          onRetry: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La capture guidée s'appuie sur ML Kit, non disponible en navigateur :
    // sur le web on affiche un message plutôt que d'initialiser la caméra.
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture photo')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smartphone, size: 56),
                SizedBox(height: 16),
                Text(
                  "La capture photo et l'analyse se font sur l'application "
                  'mobile. Le profil et le diagnostic sont déjà enregistrés.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PoseCaptureScreen(
      cameras: cameras,
      onCompleted: (shots) => _onCaptureCompleted(context, ref, shots),
    );
  }
}
```

- [ ] **Step 3: Vérifier**

Run: `cd frontend && flutter analyze`
Expected: No issues found (ou uniquement des infos préexistantes, aucune erreur)

Si `result_screen.dart` (ancien écran âge/sexe) référence `AnalyzingScreen` quelque part, il n'est plus appelé par le flux mais doit continuer à compiler — l'ancien `AnalysisResult` reste importable depuis `analysis_api.dart`.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/analyzing_screen.dart frontend/lib/capture/capture_flow.dart
git commit -m "feat(frontend): flux de capture branché sur /v1/skin/analyze (4 photos)"
```

---

### Task 15: Vérification de bout en bout (manuelle)

**Files:** aucun (vérification).

- [ ] **Step 1: Préparer l'environnement**

1. Ajouter les clés Face++ réelles dans `backend/.env` (`FACEPP_API_KEY`, `FACEPP_API_SECRET`, `ANALYSIS_ENGINE=facepp`).
2. `cd backend && pip install -r requirements.txt -r requirements-dev.txt`
3. Seed : `python -m scripts.seed_condition_map`
   Expected: plusieurs centaines/milliers de lignes insérées (catalogue de 2832 produits).

- [ ] **Step 2: Suite de tests complète**

Run: `cd backend && python -m pytest tests -v`
Expected: tous les tests passent.

- [ ] **Step 3: Test API réel (curl)**

1. `uvicorn app.main:app --reload` (depuis `backend/`)
2. Login + appel avec 4 vraies photos de visage (commande complète dans la
   section « Analyse de peau » du `backend/README.md`).
   Expected: JSON 200 avec `skin_type`, 7 `conditions`, `recommendations`
   non vides, `disclaimer_fr`. Vérifier en base :
   `SELECT id, pharmacy_id, client_id, skin_type FROM skin_analyses;`
3. Cas d'erreur : renvoyer une photo floue/sombre → 422 avec message FR.

- [ ] **Step 4: Test app Flutter**

1. `adb reverse tcp:8000 tcp:8000` puis `cd frontend && flutter run` sur l'appareil.
2. Login (`test@lumina.com` / `lumina123`) → nouveau client ou client existant
   → questionnaire → capture des 4 vues → validation → écran « Analyse de
   votre peau… » → écran résultat : type de peau, conditions ≥ 30 avec barres,
   produits avec raisons FR, disclaimer visible en bas.
3. Vérifier que `skin_analyses.client_id` correspond bien au client de la session.

- [ ] **Step 5: Commit final éventuel**

Si des ajustements ont été nécessaires (seuils, copies FR), les committer :

```bash
git add -A backend frontend
git commit -m "fix: ajustements issus de la vérification de bout en bout"
```
