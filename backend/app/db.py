"""Connexion base de données (PostgreSQL via SQLAlchemy).

L'URL est lue depuis la variable d'environnement `DATABASE_URL` (fichier
`.env`, non versionné). Par défaut on pointe sur la base locale `ismouda`
(pharmacies, clients, analyses). Le catalogue `visage_products` est lu
depuis `CATALOG_DATABASE_URL` (base Votrepara) s'il est défini.
"""

from __future__ import annotations

import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv(override=True)

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/ismouda",
)
# Catalogue produits Visage (Votrepara). Vide = même base que DATABASE_URL.
CATALOG_DATABASE_URL = os.getenv("CATALOG_DATABASE_URL", "").strip()

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
catalog_engine = (
    create_engine(CATALOG_DATABASE_URL, pool_pre_ping=True)
    if CATALOG_DATABASE_URL
    else engine
)
CatalogSessionLocal = sessionmaker(
    autocommit=False, autoflush=False, bind=catalog_engine
)
Base = declarative_base()


def get_db():
    """Dépendance FastAPI : fournit une session puis la referme."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_catalog_db():
    """Session lecture du catalogue `visage_products` (base Votrepara)."""
    db = CatalogSessionLocal()
    try:
        yield db
    finally:
        db.close()
