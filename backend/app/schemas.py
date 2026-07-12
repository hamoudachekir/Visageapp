"""Schémas Pydantic — contrat d'entrée/sortie de l'API.

Aligné sur le champ `demographics` du profil client décrit dans le plan
(section 3.4). Pour le MVP on ne renvoie que l'âge estimé et le sexe.
"""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .skin.age import real_age_from_birth_date


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


class ClientOut(ClientIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    # Redéclaré sans validateur : une ligne en base hors bornes (client devenu
    # centenaire…) ne doit jamais faire échouer la sérialisation de sortie.
    birth_date: date | None = None

    # En Pydantic v2, un @field_validator est hérité indépendamment du type du
    # champ : re-déclarer `birth_date` seul ne suffit pas à retirer le
    # validateur de ClientIn. On le neutralise donc explicitement ici — la
    # validation 13-110 ans reste appliquée en ENTRÉE (ClientIn/ClientUpdate),
    # jamais en sortie.
    @field_validator("birth_date")
    @classmethod
    def _valide_birth_date(cls, v: date | None) -> date | None:
        return v


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
