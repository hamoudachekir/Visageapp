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
