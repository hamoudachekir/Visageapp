"""Schémas Pydantic — contrat d'entrée/sortie de l'API.

Aligné sur le champ `demographics` du profil client décrit dans le plan
(section 3.4). Pour le MVP on ne renvoie que l'âge estimé et le sexe.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class Demographics(BaseModel):
    """Estimation démographique du visage principal."""

    age_estime: int = Field(..., description="Âge apparent estimé, en années.")
    sexe: str = Field(..., description="Sexe prédit : 'Homme' ou 'Femme'.")


class AnalyzeResponse(BaseModel):
    """Réponse de /v1/analyze."""

    ok: bool
    raison: str | None = Field(
        default=None,
        description="Renseigné uniquement si ok=False (ex. aucun_visage_detecte).",
    )
    moteur: str = Field(default="insightface")
    nb_visages: int = Field(default=0, description="Nombre de visages détectés.")
    confiance: float | None = Field(
        default=None, description="Score de détection du visage principal (0–1)."
    )
    demographics: Demographics | None = None
