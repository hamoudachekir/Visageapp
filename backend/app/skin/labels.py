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
