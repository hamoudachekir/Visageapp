"""Modèles SQLAlchemy — isolation multi-tenant par pharmacie.

Chaque pharmacie possède son compte (`pharmacies`) et ses propres clients
(`clients`, rattachés via `pharmacy_id`). Le catalogue `visage_products`
existant n'est pas mappé ici (lecture seule pour l'instant).
"""

from __future__ import annotations

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
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
