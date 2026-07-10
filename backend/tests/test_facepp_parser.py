"""Tests du parser Face++ -> schéma unifié (aucun appel réseau)."""
from app.skin.facepp import parse_skinanalyze
from samples import FACEPP_SAMPLE_RESULT


def test_scores_unifies():
    r = parse_skinanalyze(FACEPP_SAMPLE_RESULT)
    assert r.scores["acne"] == 62          # présent -> confiance*100
    assert r.scores["blackheads"] == 55
    assert r.scores["dark_spots"] == 12    # absent -> (1-confiance)*100
    assert r.scores["dark_circles"] == 71
    assert r.scores["wrinkles"] == 52      # max des 5 sous-indicateurs
    assert r.scores["enlarged_pores"] == 38  # moyenne des 4 zones
    assert r.scores["redness"] == 0        # non fourni par Face++ (Phase 2)


def test_zones():
    r = parse_skinanalyze(FACEPP_SAMPLE_RESULT)
    assert r.zones["wrinkles"] == ["eyes", "nasolabial"]
    assert r.zones["enlarged_pores"] == ["forehead", "chin"]
    assert r.zones["dark_circles"] == ["eyes"]


def test_type_de_peau():
    assert parse_skinanalyze(FACEPP_SAMPLE_RESULT).skin_type == "oily"


def test_champs_absents_tolerants():
    r = parse_skinanalyze({})
    assert r.skin_type == "normal"
    assert all(v == 0 for v in r.scores.values())
