"""Modèles SQLAlchemy — isolation multi-tenant par pharmacie.

Chaque pharmacie possède son compte (`pharmacies`) et ses propres clients
(`clients`, rattachés via `pharmacy_id`). Le catalogue `visage_products`
existant n'est pas mappé ici (lecture seule pour l'instant).
"""

from __future__ import annotations

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    LargeBinary,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.orm import relationship

from .db import Base


class Pharmacy(Base):
    __tablename__ = "pharmacies"

    id = Column(Integer, primary_key=True)
    nom = Column(String, nullable=False)
    email = Column(String, nullable=False, unique=True, index=True)
    password_hash = Column(String, nullable=False)
    telephone = Column(String, nullable=True)
    adresse = Column(String, nullable=True)
    ville = Column(String, nullable=True)
    description = Column(String, nullable=True)
    logo_bytes = Column(LargeBinary, nullable=True)
    logo_mime = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    clients = relationship("Client", back_populates="pharmacy")


class Client(Base):
    __tablename__ = "clients"

    id = Column(Integer, primary_key=True)
    pharmacy_id = Column(
        Integer, ForeignKey("pharmacies.id"), nullable=False, index=True
    )
    prenom = Column(String, nullable=False)
    nom = Column(String, nullable=False)
    telephone = Column(String, nullable=False, index=True)
    email = Column(String, nullable=True)
    peau_sensible = Column(String, nullable=False, default="non")
    birth_date = Column(Date, nullable=True)  # pour l'« âge de la peau »
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    pharmacy = relationship("Pharmacy", back_populates="clients")
    diagnostics = relationship("Diagnostic", back_populates="client")


class Diagnostic(Base):
    """Un diagnostic = une visite/analyse d'un client (questionnaire + résultat CV).

    L'âge et le sexe restent NULL tant que l'analyse photo (mobile) n'a pas eu lieu.
    """

    __tablename__ = "diagnostics"

    id = Column(Integer, primary_key=True)
    client_id = Column(Integer, ForeignKey("clients.id"), nullable=False, index=True)
    pharmacy_id = Column(
        Integer, ForeignKey("pharmacies.id"), nullable=False, index=True
    )
    type_peau = Column(String, nullable=False)
    tendance_acneique = Column(String, nullable=False)
    sensibilite_cutanee = Column(String, nullable=False)
    age_estime = Column(Integer, nullable=True)
    sexe = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    client = relationship("Client", back_populates="diagnostics")


class SkinAnalysis(Base):
    """Une analyse de peau (4 photos) — seuls les résultats JSON sont stockés."""

    __tablename__ = "skin_analyses"

    id = Column(Integer, primary_key=True)
    pharmacy_id = Column(
        Integer, ForeignKey("pharmacies.id"), nullable=False, index=True
    )
    client_id = Column(Integer, ForeignKey("clients.id"), nullable=True, index=True)
    skin_type = Column(String, nullable=False)
    estimated_age = Column(Integer, nullable=True)  # estimation IA — jamais exacte
    real_age = Column(Integer, nullable=True)
    skin_age_delta = Column(Integer, nullable=True)
    results_json = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ConditionProductMap(Base):
    """Mapping condition (ou skin_type_*) -> produit recommandable."""

    __tablename__ = "condition_product_map"

    id = Column(Integer, primary_key=True)
    condition_code = Column(String(30), nullable=False, index=True)
    skin_type = Column(String(15), nullable=True)  # NULL = tout type de peau
    product_id = Column(Integer, ForeignKey("visage_products.id"), nullable=False)
    priority = Column(Integer, nullable=False, default=0)
    min_age = Column(Integer, nullable=True)  # NULL = tout âge
    max_age = Column(Integer, nullable=True)


class VisageProduct(Base):
    """Mapping lecture seule du catalogue existant (colonnes utilisées seulement).

    La table réelle a plus de colonnes (dont des ARRAY PostgreSQL) : on ne
    mappe que ce dont le module skin a besoin, ce qui garde les tests
    compatibles sqlite. `create_all` ne modifie jamais une table existante.
    """

    __tablename__ = "visage_products"

    id = Column(Integer, primary_key=True)
    sub = Column(Text)
    brand = Column(Text)
    name = Column(Text)
    description = Column(Text)
    price = Column(Numeric)
    image_url = Column(Text)
    in_stock = Column(Boolean)
    active = Column(Boolean)
