"""Seed de condition_product_map depuis les slugs `sub` de visage_products.

Idempotent : vide la table puis réinsère. Usage (depuis backend/) :
    python -m scripts.seed_condition_map
"""
from __future__ import annotations

from app.db import Base, SessionLocal, engine
from app.models import ConditionProductMap, VisageProduct

# condition -> [(slug de sous-catégorie, priorité)]
CONDITION_SUBS: dict[str, list[tuple[str, int]]] = {
    "wrinkles": [("soins-anti-age-rides", 10)],
    "dark_spots": [
        ("soins-anti-taches-depigmentants", 10),
        ("soins-eclaircissants", 5),
    ],
    "acne": [("soins-peau-grasse-mixte-acne", 10)],
    "redness": [
        ("soins-anti-rougeurs-sensible", 10),
        ("soins-apaisants", 7),
        ("eaux-thermales", 4),
    ],
    "dark_circles": [("yeux-levres", 10)],
    "blackheads": [
        ("masques-gommages", 8),
        ("soins-peau-grasse-mixte-acne", 6),
    ],
    "enlarged_pores": [
        ("masques-gommages", 8),
        ("soins-peau-grasse-mixte-acne", 6),
    ],
    # Recommandations de base liées au type de peau détecté.
    "skin_type_dry": [
        ("peaux-seches", 10),
        ("soins-hydratants-nourrissants", 6),
    ],
    "skin_type_oily": [("demaquillants-nettoyants", 5)],
    "skin_type_combination": [
        ("soins-peau-grasse-mixte-acne", 8),
        ("demaquillants-nettoyants", 5),
    ],
    "skin_type_normal": [
        ("soins-hydratants-nourrissants", 8),
        ("demaquillants-nettoyants", 4),
    ],
}


def seed(db) -> int:
    """Vide puis repeuple la table. Renvoie le nombre de lignes insérées."""
    db.query(ConditionProductMap).delete()
    total = 0
    for condition, subs in CONDITION_SUBS.items():
        for sub, priority in subs:
            product_ids = [
                row[0]
                for row in db.query(VisageProduct.id)
                .filter(VisageProduct.sub == sub)
                .all()
            ]
            db.add_all(
                ConditionProductMap(
                    condition_code=condition, product_id=pid, priority=priority
                )
                for pid in product_ids
            )
            total += len(product_ids)
    db.commit()
    return total


def main() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        print(f"{seed(db)} lignes insérées dans condition_product_map.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
