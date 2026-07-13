"""Tests de POST /v1/skin/analyze (TestClient, moteur et qualité mockés, sqlite)."""
import io

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import auth as auth_module
from app.db import Base, get_db
from app.main import app
from app.models import ConditionProductMap, Client, Pharmacy, SkinAnalysis, VisageProduct
from app.skin.analyzer import CONDITION_CODES, FaceppQuotaError, SkinPhotoResult
from app.skin.engine import EngineRunResult
from app.skin.quality import PhotoQualityError

ALL_OK = {name: "ok" for name in ["front", "left", "right", "closeup"]}


def _photo_result() -> SkinPhotoResult:
    scores = {c: 5 for c in CONDITION_CODES}
    scores["acne"] = 62
    return SkinPhotoResult(scores=scores, skin_type="oily", zones={"acne": ["chin"]})


def _files():
    return {
        name: (f"{name}.jpg", io.BytesIO(b"fake-jpeg"), "image/jpeg")
        for name in ["front", "left", "right", "closeup"]
    }


@pytest.fixture()
def api(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)

    session = Session()
    pharmacy = Pharmacy(nom="Test", email="t@t.tn", password_hash="x")
    session.add(pharmacy)
    session.add_all([
        VisageProduct(id=1, name="Gel anti-acné", brand="A", price=25.5,
                      sub="soins-peau-grasse-mixte-acne", in_stock=True, active=True),
        VisageProduct(id=2, name="Crème anti-rides", brand="B", price=30.0,
                      sub="soins-anti-age-rides", in_stock=True, active=True),
    ])
    session.commit()
    session.add_all([
        ConditionProductMap(condition_code="acne", product_id=1, priority=10),
        ConditionProductMap(condition_code="wrinkles", product_id=2, priority=10),
    ])
    session.commit()
    pharmacy_id = pharmacy.id
    session.close()

    def override_db():
        s = Session()
        try:
            yield s
        finally:
            s.close()

    def override_pharmacy():
        s = Session()
        try:
            return s.get(Pharmacy, pharmacy_id)
        finally:
            s.close()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[auth_module.get_current_pharmacy] = override_pharmacy

    monkeypatch.setattr("app.skin.quality.validate_photo", lambda raw, name: None)

    async def fake_run(photos, mode=None):
        return EngineRunResult(
            results={"front": _photo_result()}, photo_status=ALL_OK, engine="facepp"
        )

    monkeypatch.setattr("app.skin.engine.run_analysis", fake_run)

    async def fake_estimate(front_bytes, mode=None):
        return None, None

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)

    yield TestClient(app), Session
    app.dependency_overrides.clear()


def test_analyse_ok(api):
    client, Session = api
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["skin_type"] == "oily"
    assert body["disclaimer_fr"].endswith("avis dermatologique.")
    assert body["conditions"][0]["code"] == "acne"
    assert body["conditions"][0]["severity"] == "severe"
    assert body["conditions"][0]["zones"] == ["chin"]
    assert len(body["conditions"]) == 7  # toutes les conditions, triées par score
    ids = [r["product_id"] for r in body["recommendations"]]
    assert 1 in ids and 2 not in ids  # rides à 5 -> sous le seuil
    assert "acné" in body["recommendations"][0]["reason_fr"]

    s = Session()
    saved = s.query(SkinAnalysis).one()
    assert saved.skin_type == "oily"
    assert saved.results_json["engine"] == "facepp"
    s.close()


def test_photo_floue_422(api, monkeypatch):
    client, _ = api

    def reject(raw, name):
        raise PhotoQualityError(f"{name} : photo floue.")

    monkeypatch.setattr("app.skin.quality.validate_photo", reject)
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 422
    assert "floue" in res.json()["detail"]


def test_quota_502(api, monkeypatch):
    client, _ = api

    async def fail(photos, mode=None):
        raise FaceppQuotaError("Service d'analyse temporairement indisponible (quota Face++).")

    monkeypatch.setattr("app.skin.engine.run_analysis", fail)
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 502
    assert "quota" in res.json()["detail"]


def test_client_autre_pharmacie_404(api):
    client, Session = api
    s = Session()
    autre = Pharmacy(nom="Autre", email="a@a.tn", password_hash="x")
    s.add(autre)
    s.commit()
    intrus = Client(pharmacy_id=autre.id, prenom="X", nom="Y", telephone="1")
    s.add(intrus)
    s.commit()
    intrus_id = intrus.id
    s.close()

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(intrus_id)}
    )
    assert res.status_code == 404


def test_client_de_la_pharmacie_rattache(api):
    client, Session = api
    s = Session()
    mien = Client(pharmacy_id=1, prenom="A", nom="B", telephone="2")
    s.add(mien)
    s.commit()
    mien_id = mien.id
    s.close()

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(mien_id)}
    )
    assert res.status_code == 200
    s = Session()
    assert s.query(SkinAnalysis).one().client_id == mien_id
    s.close()


from datetime import date

from app.skin.age import AgeEstimate


def test_age_null_si_estimateur_echoue(api):
    client, Session = api
    res = client.post("/v1/skin/analyze", files=_files())
    assert res.status_code == 200
    assert res.json()["age"] is None
    s = Session()
    saved = s.query(SkinAnalysis).one()
    assert saved.estimated_age is None and saved.skin_age_delta is None
    s.close()


def test_bloc_age_complet_avec_birth_date(api, monkeypatch):
    client, Session = api

    async def fake_estimate(front_bytes, mode=None):
        return AgeEstimate(age=32, sexe="Homme"), "facepp"

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)

    s = Session()
    today = date.today()
    # date fixe au 15 juin pour éviter le cas 29 février ; âge = 28 ans révolus.
    birth = date(today.year - 28, 6, 15)
    if (today.month, today.day) < (6, 15):
        birth = date(today.year - 29, 6, 15)
    mien = Client(
        pharmacy_id=1, prenom="A", nom="B", telephone="2",
        birth_date=birth,
    )
    s.add(mien)
    s.commit()
    mien_id = mien.id
    s.close()

    res = client.post(
        "/v1/skin/analyze", files=_files(), data={"client_id": str(mien_id)}
    )
    assert res.status_code == 200, res.text
    age = res.json()["age"]
    assert age == {
        "estimated_age": 32,
        "real_age": 28,
        "skin_age_delta": 4,
        "message_fr": "Votre peau paraît 4 ans de plus — voici des soins ciblés.",
    }
    s = Session()
    saved = s.query(SkinAnalysis).order_by(SkinAnalysis.id.desc()).first()
    assert (saved.estimated_age, saved.real_age, saved.skin_age_delta) == (32, 28, 4)
    assert saved.results_json["age_engine"] == "facepp"
    s.close()


def test_bloc_age_sans_birth_date(api, monkeypatch):
    client, _ = api

    async def fake_estimate(front_bytes, mode=None):
        return AgeEstimate(age=32, sexe=None), "local"

    monkeypatch.setattr("app.skin.router.estimate_age", fake_estimate)
    res = client.post("/v1/skin/analyze", files=_files())
    age = res.json()["age"]
    assert age["estimated_age"] == 32
    assert age["real_age"] is None and age["skin_age_delta"] is None
    assert age["message_fr"] == "Votre peau paraît 32 ans (estimation)."


def test_brands_liste_triee(api):
    client, _ = api
    res = client.get("/v1/skin/brands")
    assert res.status_code == 200
    assert res.json()["brands"] == ["A", "B"]


def test_brands_exclut_inactifs_null_et_vides(api):
    client, Session = api
    s = Session()
    s.add_all([
        VisageProduct(id=3, name="X", brand="Inactivo", price=1, in_stock=True, active=False),
        VisageProduct(id=4, name="Y", brand=None, price=1, in_stock=True, active=True),
        VisageProduct(id=5, name="Z", brand="  ", price=1, in_stock=True, active=True),
        VisageProduct(id=6, name="W", brand="Cerave", price=1, in_stock=True, active=True),
    ])
    s.commit()
    s.close()
    res = client.get("/v1/skin/brands")
    assert res.json()["brands"] == ["A", "B", "Cerave"]


def test_description_dans_reco(api):
    client, Session = api
    s = Session()
    p = s.get(VisageProduct, 1)
    p.description = "Nettoie en douceur."
    s.commit()
    s.close()
    res = client.post("/v1/skin/analyze", files=_files())
    reco = res.json()["recommendations"][0]
    assert reco["description"] == "Nettoie en douceur."
