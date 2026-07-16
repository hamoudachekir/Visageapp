# Persistance clients & diagnostics (multi-tenant) — design spec

**Date** : 2026-06-23
**Statut** : Approuvé par l'utilisateur en conversation.

## Contexte

Suite de l'auth multi-tenant ([2026-06-22](2026-06-22-auth-pharmacie-multi-tenant-design.md)).
Aujourd'hui le dépôt clients est en mémoire (`InMemoryClientRepository`) : rien n'est
persisté. L'utilisateur veut qu'un « Nouveau client » soit enregistré en base
(profil + réponses au questionnaire), pour qu'il revienne plus tard via « Client
existant » + numéro de téléphone et retrouve son profil.

Contrainte actée : la capture photo guidée utilise Google ML Kit, **non supporté sur
le web**. L'utilisateur teste dans Chrome → en web la caméra est désactivée (message
« capture sur l'appareil mobile ») ; la capture guidée reste sur le téléphone.

## Scope

**Inclus :**
- Table `diagnostics` (un enregistrement par visite/analyse), scopée par pharmacie.
- Endpoints backend : créer un diagnostic, lister les diagnostics d'un client.
- `ApiClientRepository` (remplace `InMemoryClientRepository`) : recherche par
  téléphone + création client, via l'API, avec le token JWT.
- Sauvegarde du client + diagnostic **après la dernière question du questionnaire**
  (avant l'étape caméra), pour ne rien perdre si la caméra est sautée (web) ou échoue.
- Flux « Client existant » : recherche par téléphone → préremplit le profil → nouvelle
  visite (nouveau diagnostic rattaché au même client).
- Caméra web : `CaptureFlow` détecte `kIsWeb` et affiche un message au lieu d'ML Kit.

**Exclus (hors scope) :**
- Analyse photo réelle dans Chrome (nécessite l'appareil + modèle CV).
- Rattachement de l'âge/sexe au diagnostic après analyse — prévu plus tard via
  `PATCH /v1/diagnostics/{id}` sur le téléphone (colonnes déjà nullable).
- Édition / suppression de clients enregistrés.
- Restylage visuel Stitch des autres écrans.

## Modèle de données (PostgreSQL `ismouda`)

```sql
CREATE TABLE diagnostics (
    id                  SERIAL PRIMARY KEY,
    client_id           INTEGER NOT NULL REFERENCES clients(id),
    pharmacy_id         INTEGER NOT NULL REFERENCES pharmacies(id),
    type_peau           TEXT NOT NULL,
    tendance_acneique   TEXT NOT NULL,
    sensibilite_cutanee TEXT NOT NULL,
    age_estime          INTEGER,        -- rempli après analyse photo (mobile)
    sexe                TEXT,           -- idem
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`clients` existe déjà. Tables créées au démarrage via `Base.metadata.create_all`.

## Backend (token-scoped : `pharmacy_id` dérivé du JWT)

- `GET /v1/clients?telephone=` (existe) — « Client existant ».
- `POST /v1/clients` (existe) — « Nouveau client ».
- `POST /v1/diagnostics` `{client_id, type_peau, tendance_acneique, sensibilite_cutanee}`
  → crée le diagnostic (vérifie que le client appartient à la pharmacie du token).
- `GET /v1/clients/{id}/diagnostics` → historique des visites du client.

Toute route vérifie que `client_id` appartient bien à la pharmacie du token
(404 sinon) — pas de fuite inter-tenant.

## Frontend

- `ClientProfile` : ajout d'un `int? id` (null = non persisté) + `fromJson`.
- `lib/models/diagnostic.dart` : modèle léger (réponses + age/sexe nullable).
- `ClientRepository` (interface) :
  - `Future<ClientProfile?> findByPhone(String telephone)`
  - `Future<ClientProfile> save(ClientProfile client)` (renvoie l'id attribué)
  - `Future<void> saveDiagnostic(int clientId, QuestionnaireAnswers answers)`
- `ApiClientRepository` : implémente l'interface via `http` + header
  `Authorization: Bearer <token>`. Le token vient de `authProvider` :
  `clientRepositoryProvider = Provider((ref) => ApiClientRepository(token: ref.watch(authProvider).session?.token))`.
- `questionnaire_screen.dart` (dernière étape) :
  1. Si `client.id == null` → `save(client)` (création) et récupère l'id.
  2. `saveDiagnostic(id, answers)`.
  3. Web → écran de confirmation « Client enregistré ✓, capture sur mobile ».
     Mobile → `CaptureFlow`.
- `existing_client_screen.dart` : recherche via `findByPhone` (API) ; si trouvé,
  préremplit le profil et continue vers le questionnaire.
- `capture_flow.dart` : si `kIsWeb`, écran message au lieu d'initialiser la caméra.

## Gestion des erreurs

- Réseau / backend indisponible : message inline, même motif que l'auth ; la
  navigation ne plante pas.
- 401 (token expiré) sur un appel : remonté comme erreur ; (déconnexion/redirection
  login traitée globalement plus tard).
- « Client existant » sans correspondance : message « Aucun client trouvé pour ce
  numéro ».

## Tests

- Backend (manuel/curl) : création client → création diagnostic → liste diagnostics ;
  un diagnostic d'une pharmacie n'est pas visible/relié à une autre (isolation).
- Frontend (manuel, Chrome) : Nouveau client → questionnaire → « enregistré » →
  retrouvé via Client existant + téléphone (profil prérempli).
