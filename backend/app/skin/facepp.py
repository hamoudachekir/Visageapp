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
