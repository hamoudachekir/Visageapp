# Authentification pharmacie & isolation multi-tenant — design spec

**Date** : 2026-06-22
**Statut** : Approuvé par l'utilisateur en conversation, implémentation à venir.

## Contexte

Suite-à au sous-projet précédent (onboarding client, [2026-06-20](2026-06-20-client-onboarding-flow-design.md)),
qui notait explicitement le login par pharmacie comme prochain sous-projet et excluait
tout backend de persistance. L'utilisateur a fourni :

- Un exemple HTML (look "Ismouda" — Inter, teal, logo feuille) pour l'écran de
  connexion, issu d'un dossier de maquettes Stitch plus large (`accueil`,
  `choix_de_session`, `création_profil`, `recherche_client`, `questionnaire`,
  `capture_photo`, `validation_photos`, `analyse_en_cours`, `résultat_diagnostic`).
- Le besoin métier : chaque pharmacie a son propre compte, ses propres clients, et
  (plus tard) ses propres produits.
- Une base PostgreSQL locale déjà existante (`votrepara`) contenant une table
  `visage_products` (2832 lignes de catalogue produits réel).

Le dossier de maquettes Stitch complet n'est **pas** dans le scope de ce sous-projet
(c'est un restylage visuel séparé, déjà identifié comme tel en conversation). Ce
sous-projet couvre uniquement la fondation auth + isolation des données.

Décision actée en cours de route : la base de données passe de "SQLite à créer" à
"PostgreSQL existant" — une nouvelle base dédiée `ismouda` a été créée sur le
serveur PostgreSQL 16 local, avec la table `visage_products` copiée depuis
`votrepara` (schéma + 2832 lignes, vérifié). `votrepara` n'est pas modifiée.

## Scope

**Inclus :**
- Table `pharmacies` (compte = pharmacie) et migration de `clients` vers Postgres,
  scopée par `pharmacy_id`.
- Endpoint `POST /v1/auth/login` (email + mot de passe → JWT).
- Script admin de création de compte pharmacie (pas de signup public).
- Écran de connexion Flutter (`login_screen.dart`), structure reprise du HTML fourni,
  restylée dans le thème bleu "Clinical Spa" actuel (pas le look teal Ismouda — ce
  sera traité dans le sous-projet de restylage visuel séparé).
- Persistance de session (token stocké via `flutter_secure_storage`, connexion
  conservée entre lancements de l'app).
- Déconnexion via le badge pharmacie dans `AppHeader` (menu contextuel).
- Routage : `/` (splash) redirige vers `/login` ou `/home` selon l'état de session ;
  nouvelle route `/login`.
- `ClientRepository` : remplacement de `InMemoryClientRepository` par une
  implémentation API, scopée par pharmacie côté backend (le `pharmacy_id` vient du
  token, jamais du client).

**Exclus (hors scope, décidé explicitement) :**
- Restylage visuel complet vers le look Ismouda (Stitch) — sous-projet séparé futur.
- Table/CRUD `products` — la table `visage_products` existe déjà dans la base
  `ismouda` (copiée), mais aucun écran/endpoint ne l'exploite encore. Le FK
  `pharmacy_id` posé maintenant pour `clients` sera réutilisé tel quel le jour où
  les produits seront scopés par pharmacie (à définir : produits partagés entre
  pharmacies vs. catalogue par pharmacie — question ouverte pour ce sous-projet
  futur, pas tranchée ici).
- Flux "Demander un accès" complet (file d'attente + validation admin) — un simple
  lien `mailto:` suffit pour l'instant.
- Réinitialisation de mot de passe ("Mot de passe oublié ?" est un lien inerte qui
  affiche un message de contact, pas un flux fonctionnel).

## Modèle de données (PostgreSQL, base `ismouda`)

```sql
CREATE TABLE pharmacies (
    id            SERIAL PRIMARY KEY,
    nom           TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE clients (
    id            SERIAL PRIMARY KEY,
    pharmacy_id   INTEGER NOT NULL REFERENCES pharmacies(id),
    prenom        TEXT NOT NULL,
    nom           TEXT NOT NULL,
    telephone     TEXT NOT NULL,
    email         TEXT,
    peau_sensible TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_clients_pharmacy_telephone ON clients(pharmacy_id, telephone);
```

`visage_products` reste tel que copié (aucune colonne `pharmacy_id` ajoutée dans ce
sous-projet, puisque la question "produits partagés vs. par pharmacie" n'est pas
tranchée).

**Point de vigilance RGPD** (déjà noté dans le spec précédent, §8.2 du plan) : la
table `clients` persiste désormais des données personnelles au-delà de la session
en mémoire actuelle. Pas de changement de périmètre RGPD supplémentaire dans ce
sous-projet (mêmes champs qu'aujourd'hui), mais la persistance elle-même devient
réelle — à garder en tête pour une politique de rétention/suppression future.

## Architecture backend

- Ajout de `sqlalchemy`, `psycopg2-binary`, `passlib[bcrypt]`, `python-jose[cryptography]`
  à `requirements.txt`.
- `DATABASE_URL` lu depuis `.env` (gitignored) : `postgresql://postgres:postgres@localhost:5432/ismouda`.
- `app/db.py` : engine SQLAlchemy + session factory + `Base.metadata.create_all()`
  au démarrage (pas de migration Alembic pour ce MVP — la table `clients` est
  neuve, pas de données existantes à migrer).
- `app/models.py` : modèles SQLAlchemy `Pharmacy`, `Client`.
- `app/auth.py` : hash/vérification mot de passe (passlib), création/décodage JWT
  (expiration 30 jours), dépendance FastAPI `get_current_pharmacy` (lit
  `Authorization: Bearer <token>`, 401 si absent/invalide/expiré).
- Nouveaux endpoints :
  - `POST /v1/auth/login` → `{email, password}` → `{token, pharmacy: {id, nom}}`.
  - `GET /v1/clients?telephone=...` (protégé) → cherche uniquement dans les clients
    du `pharmacy_id` du token.
  - `POST /v1/clients` (protégé) → crée un client rattaché au `pharmacy_id` du token.
- `backend/scripts/create_pharmacy.py` : script CLI (`python -m scripts.create_pharmacy
  --nom "..." --email "..." --password "..."`) pour provisionner un compte
  manuellement.

## Architecture frontend

- `lib/services/auth_api.dart` : client HTTP (même style que `analysis_api.dart`)
  — `login(email, password) -> AuthResult {token, pharmacyId, nom}`.
- `lib/data/auth_repository.dart` : enveloppe `auth_api.dart` + lecture/écriture du
  token via `flutter_secure_storage`.
- `lib/providers/auth_provider.dart` : `authProvider` (Riverpod `NotifierProvider`)
  — état `{pharmacyId, nom, token}` ou `null`, méthodes `login()`, `logout()`,
  `restoreSession()` (appelée au démarrage).
- `lib/data/client_repository.dart` : nouvelle implémentation `ApiClientRepository`
  (remplace `InMemoryClientRepository` dans `clientRepositoryProvider`), envoie le
  token courant en en-tête `Authorization` sur chaque appel.
- `lib/screens/login_screen.dart` : nouvel écran, structure du HTML fourni
  (logo + titre, carte blanche avec champs email/mot de passe + icônes, lien mot de
  passe oublié inerte, bouton "Se connecter" pleine largeur avec état de chargement
  via `CustomButton`, lien "Demander un accès" en `mailto:`, `_StatusFooter` réutilisé)
  — thème bleu "Clinical Spa" actuel, pas le look teal Ismouda du HTML source.
- `lib/widgets/status_footer.dart` : extraction du `_StatusFooter` actuellement privé
  dans `home_screen.dart` vers un widget partagé (utilisé par `home_screen.dart` et
  `login_screen.dart`).
- `lib/widgets/app_header.dart` : le badge pharmacie devient un `PopupMenuButton`
  avec une seule entrée "Se déconnecter" → `authProvider.logout()` puis
  `context.go('/login')`.
- `lib/router/app_router.dart` : nouvelle route `/login` ; la route `/` (splash)
  appelle `authProvider.restoreSession()` avant de décider `/login` vs `/home`.

## Gestion des erreurs

- Identifiants invalides (401) : message inline sous le champ mot de passe
  ("Email ou mot de passe incorrect"), pas de dialogue/exception.
- Erreur réseau (timeout, backend down) : message inline générique, même pattern
  que les erreurs existantes de `analysis_api.dart`.
- Token expiré/invalide sur un appel API ultérieur (ex. `GET /v1/clients`) : 401 →
  le frontend efface la session et redirige vers `/login`.

## Tests

- Backend (pytest) : login avec identifiants valides/invalides ; un client créé par
  la pharmacie A n'est pas visible via le token de la pharmacie B (test d'isolation
  multi-tenant, le cœur de ce sous-projet).
- Frontend : vérification manuelle (pas de suite de tests widget existante dans le
  projet actuellement) — connexion réussie, échec d'identifiants, persistance de
  session après redémarrage de l'app, déconnexion.
