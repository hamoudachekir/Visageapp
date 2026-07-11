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
