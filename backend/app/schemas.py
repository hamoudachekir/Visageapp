"""Schémas Pydantic — contrat d'entrée/sortie de l'API.

Aligné sur le champ `demographics` du profil client décrit dans le plan
(section 3.4). Pour le MVP on ne renvoie que l'âge estimé et le sexe.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


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


# ───────────────────────── Auth & multi-tenant ─────────────────────────


class LoginRequest(BaseModel):
    email: str
    password: str


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


class LoginResponse(BaseModel):
    token: str
    pharmacy: PharmacyOut


class ClientIn(BaseModel):
    prenom: str
    nom: str
    telephone: str
    email: str | None = None
    peau_sensible: str = "non"


class ClientOut(ClientIn):
    model_config = ConfigDict(from_attributes=True)

    id: int


class DiagnosticIn(BaseModel):
    client_id: int
    type_peau: str
    tendance_acneique: str
    sensibilite_cutanee: str


class DiagnosticOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    client_id: int
    type_peau: str
    tendance_acneique: str
    sensibilite_cutanee: str
    age_estime: int | None = None
    sexe: str | None = None
    created_at: datetime | None = None
