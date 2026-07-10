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
