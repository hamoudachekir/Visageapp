"""Moteur de recommandation produits — cœur pur (testable sans DB) + fetchers SQL."""
from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy.orm import Session

from ..models import ConditionProductMap, VisageProduct
from .labels import RECOMMEND_THRESHOLD, severity

# Score fictif attribué au type de peau détecté (déclenche les produits de base).
SKIN_TYPE_BASE_SCORE = 40
TOP_N = 6

# Impact de l'âge sur les recommandations (spec 2026-07-11).
AGE_DELTA_BOOST = 1.5        # skin_age_delta >= 3 -> rides & taches boostées
WRINKLES_AGE_MIN = 35        # règle anti-âge : rides seulement si âge >= 35...
WRINKLES_SCORE_OVERRIDE = 40  # ...ou score >= 40 (ou âge inconnu)

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
    description: str | None
    reason_fr: str
    matched_conditions: list[str]
    sub: str | None = None
    ean: str | None = None
    source_url: str | None = None
    old_price: float | None = None
    rating: float | None = None


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
    age: int | None = None,
    skin_age_delta: int | None = None,
) -> list[Recommendation]:
    """Conditions >= seuil -> produits mappés -> rang (sévérité x priorité) -> top 6.

    `age` (réel sinon estimé) filtre les lignes min_age/max_age et applique la
    règle anti-âge ; `skin_age_delta` >= 3 booste rides et taches brunes.
    """
    effective = {c: s for c, s in scores.items() if s >= RECOMMEND_THRESHOLD}
    # Règle anti-âge : rides seulement si score fort OU âge >= 35 OU âge inconnu.
    if (
        "wrinkles" in effective
        and age is not None
        and age < WRINKLES_AGE_MIN
        and effective["wrinkles"] < WRINKLES_SCORE_OVERRIDE
    ):
        del effective["wrinkles"]
    effective[f"skin_type_{skin_type}"] = SKIN_TYPE_BASE_SCORE

    boosted = {"wrinkles", "dark_spots"} if (skin_age_delta or 0) >= 3 else set()

    candidates: dict[int, dict] = {}
    for mapping in mappings:
        condition = mapping["condition_code"]
        if condition not in effective:
            continue
        if mapping.get("skin_type") and mapping["skin_type"] != skin_type:
            continue
        # Filtre d'âge par ligne : NULL = tout âge ; âge inconnu = pas de filtre.
        if age is not None:
            if mapping.get("min_age") is not None and age < mapping["min_age"]:
                continue
            if mapping.get("max_age") is not None and age > mapping["max_age"]:
                continue
        product = products.get(mapping["product_id"])
        if not product or not product.get("active") or not product.get("in_stock"):
            continue
        entry = candidates.setdefault(
            mapping["product_id"], {"rank": 0.0, "matched": []}
        )
        # priorité 0 traitée comme 1 pour ne pas annuler le rang.
        weight = effective[condition] * max(int(mapping.get("priority") or 0), 1)
        if condition in boosted:
            weight *= AGE_DELTA_BOOST
        entry["rank"] += weight
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
                description=product.get("description"),
                reason_fr=build_reason_fr(entry["matched"], scores, skin_type),
                matched_conditions=[
                    c for c in entry["matched"] if not c.startswith("skin_type_")
                ],
                sub=product.get("sub"),
                ean=product.get("ean"),
                source_url=product.get("source_url"),
                old_price=product.get("old_price"),
                rating=product.get("rating"),
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
            "min_age": r.min_age,
            "max_age": r.max_age,
        }
        for r in rows
    ]


def fetch_products(db: Session, product_ids: list[int]) -> dict[int, dict]:
    """Produits Visage par id — détails catalogue (prix converti en float)."""
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
            "old_price": float(r.old_price) if r.old_price is not None else None,
            "rating": float(r.rating) if r.rating is not None else None,
            "image_url": r.image_url,
            "description": r.description,
            "sub": r.sub,
            "ean": r.ean,
            "source_url": r.source_url,
            "in_stock": bool(r.in_stock),
            "active": bool(r.active),
        }
        for r in rows
    }
