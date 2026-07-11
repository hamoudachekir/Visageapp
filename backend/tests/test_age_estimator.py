"""Tests de l'estimation d'âge : parser Face++ Detect (Task 1) + moteurs (Task 2)."""
import pytest

from app.skin.age import AgeEstimate, parse_detect
from app.skin.analyzer import NoFaceError

DETECT_ONE_FACE = {
    "faces": [
        {
            "face_rectangle": {"width": 200, "height": 220, "top": 10, "left": 10},
            "attributes": {
                "age": {"value": 32},
                "gender": {"value": "Male"},
            },
        }
    ]
}

DETECT_TWO_FACES = {
    "faces": [
        {
            "face_rectangle": {"width": 80, "height": 90},
            "attributes": {"age": {"value": 60}, "gender": {"value": "Female"}},
        },
        {
            "face_rectangle": {"width": 300, "height": 320},
            "attributes": {"age": {"value": 25}, "gender": {"value": "Female"}},
        },
    ]
}


def test_parse_un_visage():
    estimate = parse_detect(DETECT_ONE_FACE)
    assert estimate == AgeEstimate(age=32, sexe="Homme")


def test_parse_plusieurs_visages_prend_le_plus_grand():
    estimate = parse_detect(DETECT_TWO_FACES)
    assert estimate.age == 25
    assert estimate.sexe == "Femme"


def test_parse_aucun_visage():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": []})
    with pytest.raises(NoFaceError):
        parse_detect({})


def test_parse_attributs_absents():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": [{"face_rectangle": {"width": 200, "height": 200}}]})
