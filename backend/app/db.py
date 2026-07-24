"""Connexion base de données (PostgreSQL via SQLAlchemy).

L'URL est lue depuis la variable d'environnement `DATABASE_URL` (fichier
`.env`, non versionné). Par défaut on pointe sur la base locale `ismouda`
qui contient déjà la table `visage_products` (catalogue produits).
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

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    """Dépendance FastAPI : fournit une session puis la referme."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
