"""Tests de l'agrégation : max par condition, union des zones, vote majoritaire."""
import pytest

from app.skin.aggregate import aggregate
from app.skin.analyzer import CONDITION_CODES, SkinPhotoResult


def _photo(skin_type: str = "oily", **overrides) -> SkinPhotoResult:
    scores = {c: 0 for c in CONDITION_CODES}
    scores.update(overrides.pop("scores", {}))
    return SkinPhotoResult(scores=scores, skin_type=skin_type, **overrides)


def test_max_par_condition_et_union_zones():
    results = {
        "front": _photo(scores={"acne": 40}, zones={"acne": ["chin"]}),
        "left": _photo(scores={"acne": 62}, zones={"acne": ["left_cheek", "chin"]}),
    }
    scores, _, zones = aggregate(results)
    assert scores["acne"] == 62
    assert scores["wrinkles"] == 0
    assert zones["acne"] == ["chin", "left_cheek"]


def test_vote_majoritaire_type_de_peau():
    results = {
        "front": _photo("dry"),
        "left": _photo("oily"),
        "right": _photo("oily"),
    }
    _, skin_type, _ = aggregate(results)
    assert skin_type == "oily"


def test_egalite_tranchee_par_la_photo_de_face():
    results = {
        "front": _photo("dry"),
        "left": _photo("oily"),
        "right": _photo("oily"),
        "closeup": _photo("dry"),
    }
    _, skin_type, _ = aggregate(results)
    assert skin_type == "dry"


def test_agregation_vide_interdite():
    with pytest.raises(ValueError):
        aggregate({})
