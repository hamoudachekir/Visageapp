"""Tests du moteur de recommandation (cœur pur + fetchers sqlite)."""
from app.models import ConditionProductMap, VisageProduct
from app.skin.recommend import (
    build_reason_fr,
    build_recommendations,
    fetch_mappings,
    fetch_products,
)


def _products(n: int) -> dict[int, dict]:
    return {
        i: {
            "name": f"Produit {i}", "brand": "Marque", "price": 10.0 + i,
            "image_url": None, "in_stock": True, "active": True,
        }
        for i in range(1, n + 1)
    }


def _mapping(cond: str, pid: int, priority: int = 10, skin_type: str | None = None):
    return {
        "condition_code": cond, "product_id": pid,
        "priority": priority, "skin_type": skin_type,
    }


SCORES = {
    "acne": 62, "wrinkles": 25, "dark_spots": 45, "dark_circles": 0,
    "blackheads": 0, "enlarged_pores": 0, "redness": 0,
}


def test_seuil_et_rang():
    mappings = [
        _mapping("acne", 1, 10),
        _mapping("acne", 2, 5),
        _mapping("dark_spots", 2, 10),
        _mapping("wrinkles", 3, 10),  # 25 < 30 : jamais recommandé
        _mapping("skin_type_oily", 4, 5),
    ]
    recs = build_recommendations(SCORES, "oily", mappings, _products(4))
    ids = [r.product_id for r in recs]
    # p2 = 62*5 + 45*10 = 760 > p1 = 620 > p4 = 40*5 = 200 ; p3 exclu.
    assert ids == [2, 1, 4]
    assert recs[0].matched_conditions == ["acne", "dark_spots"]
    assert recs[2].matched_conditions == []  # match uniquement type de peau


def test_filtre_type_de_peau():
    mappings = [
        _mapping("acne", 1, 10, skin_type="dry"),   # incompatible
        _mapping("acne", 2, 10, skin_type="oily"),  # compatible
        _mapping("acne", 3, 10, skin_type=None),    # tout type
    ]
    ids = [r.product_id for r in build_recommendations(SCORES, "oily", mappings, _products(3))]
    assert 1 not in ids and set(ids) == {2, 3}


def test_produits_inactifs_ou_epuises_exclus():
    products = _products(2)
    products[1]["active"] = False
    products[2]["in_stock"] = False
    recs = build_recommendations(
        SCORES, "oily", [_mapping("acne", 1), _mapping("acne", 2)], products
    )
    assert recs == []


def test_top_6():
    mappings = [_mapping("acne", i) for i in range(1, 9)]
    assert len(build_recommendations(SCORES, "oily", mappings, _products(8))) == 6


def test_reason_fr():
    reason = build_reason_fr(["acne", "skin_type_oily"], SCORES, "oily")
    assert reason == "Recommandé pour votre acné marquée et votre peau grasse."
    seul_type = build_reason_fr(["skin_type_dry"], SCORES, "dry")
    assert seul_type == "Recommandé pour votre peau sèche."


def test_fetchers_sqlite(db_session):
    db_session.add(VisageProduct(
        id=1, sub="soins-anti-age-rides", name="Crème", brand="M",
        price=19.9, image_url="http://img", in_stock=True, active=True,
    ))
    db_session.add(ConditionProductMap(condition_code="wrinkles", product_id=1, priority=10))
    db_session.commit()

    mappings = fetch_mappings(db_session, ["wrinkles", "acne"])
    assert mappings == [
        {"condition_code": "wrinkles", "skin_type": None, "product_id": 1, "priority": 10}
    ]
    products = fetch_products(db_session, [1])
    assert products[1]["name"] == "Crème"
    assert products[1]["price"] == 19.9
