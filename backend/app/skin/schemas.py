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
    old_price: float | None = None
    rating: float | None = None
    image_url: str | None = None
    description: str | None = None
    sub: str | None = None
    ean: str | None = None
    source_url: str | None = None
    reason_fr: str
    matched_conditions: list[str] = []


class AgeOut(BaseModel):
    """Bloc âge — `estimated_age` est une estimation IA, jamais exacte."""

    estimated_age: int = Field(
        description="Âge estimé par IA sur la photo de face (estimation)."
    )
    real_age: int | None = None
    skin_age_delta: int | None = None
    message_fr: str


class SkinAnalyzeResponse(BaseModel):
    analysis_id: int
    skin_type: str
    conditions: list[ConditionOut]
    recommendations: list[RecommendationOut]
    age: AgeOut | None = None
    disclaimer_fr: str


class BrandsResponse(BaseModel):
    brands: list[str]
