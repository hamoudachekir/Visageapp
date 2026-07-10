"""Tests du seed de condition_product_map depuis les slugs `sub`."""
from app.models import ConditionProductMap, VisageProduct
from scripts.seed_condition_map import CONDITION_SUBS, seed


def _produit(pid: int, sub: str) -> VisageProduct:
    return VisageProduct(
        id=pid, sub=sub, name=f"Produit {pid}", brand="Marque",
        price=10.0, in_stock=True, active=True,
    )


def test_seed_mappe_les_sous_categories(db_session):
    db_session.add_all([
        _produit(1, "soins-anti-age-rides"),
        _produit(2, "soins-peau-grasse-mixte-acne"),
        _produit(3, "maquillage"),  # non mappé
    ])
    db_session.commit()

    total = seed(db_session)

    rows = db_session.query(ConditionProductMap).all()
    assert total == len(rows)
    codes = {(r.condition_code, r.product_id) for r in rows}
    assert ("wrinkles", 1) in codes
    assert ("acne", 2) in codes
    # le produit 2 sert aussi blackheads et enlarged_pores (priorité moindre)
    assert ("blackheads", 2) in codes
    assert ("enlarged_pores", 2) in codes
    assert all(pid != 3 for _, pid in codes)


def test_seed_idempotent(db_session):
    db_session.add(_produit(1, "soins-anti-age-rides"))
    db_session.commit()
    first = seed(db_session)
    second = seed(db_session)
    assert first == second == db_session.query(ConditionProductMap).count()


def test_toutes_les_conditions_du_seed_ont_des_slugs():
    for condition, subs in CONDITION_SUBS.items():
        assert subs, f"{condition} sans slug"
