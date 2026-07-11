# Estimation d'âge & « âge de la peau » — design spec

**Date** : 2026-07-11
**Statut** : Approuvé par l'utilisateur en conversation.

## Contexte

Suite du module d'analyse de peau ([2026-07-10](2026-07-10-skin-analysis-module-design.md)),
livré et testé de bout en bout (Face++ Phase 1). L'utilisateur veut ajouter
l'estimation d'âge : un « âge de la peau » estimé par IA sur la photo de face,
comparé à l'âge réel dérivé de la date de naissance, avec message marketing
(« Votre peau paraît X ans ») et impact sur les recommandations produits.

Décisions actées en conversation :

- **`birth_date` sur la table `clients`** — la personne analysée est un client
  (le « user » connecté est une pharmacie ; la spec initiale disait `users`).
- **Fallback local = InsightFace existant** (`vision.analyze_demographics`
  renvoie déjà l'âge et le sexe, modèle déjà chargé) — pas de deepface
  (TensorFlow inutilement lourd).
- **Migrations = script idempotent maison** (pattern
  `scripts/migrate_pharmacy_profile.py`), pas d'Alembic.
- **Flutter inclus** : date de naissance au formulaire nouveau client + carte
  âge sur l'écran résultat.

## Scope

**Inclus :**

- `app/skin/age.py` : interface `AgeEstimator`, moteurs Face++ Detect et
  InsightFace, sélection `ANALYSIS_ENGINE`, fonctions pures âge réel/message.
- Migration + modèles : `clients.birth_date`,
  `skin_analyses.{estimated_age, real_age, skin_age_delta}`,
  `condition_product_map.{min_age, max_age}`.
- `POST /v1/clients` accepte `birth_date` ; nouveau `PATCH /v1/clients/{id}`.
- `POST /v1/skin/analyze` : bloc `age` dans la réponse (ou `null`), colonnes
  persistées.
- Recommandations : filtre `min_age`/`max_age`, règle anti-âge, boost delta.
- Flutter : modèle `AgeInfo`, date picker au formulaire client, carte âge sur
  `SkinResultScreen`.
- Tests unitaires backend + test `fromJson` Dart ; README mis à jour.

**Exclus (hors scope) :**

- deepface / TensorFlow, Alembic.
- UI Flutter d'édition d'un client existant (l'endpoint PATCH est prêt ; la
  saisie se fait à la création du client).
- Modification de l'ancien `/v1/analyze` (inchangé).
- Peuplement de `min_age`/`max_age` dans le seed (colonnes à NULL par défaut ;
  la règle anti-âge est codée, le tuning par colonnes viendra à l'usage).

## Moteur d'estimation d'âge — `backend/app/skin/age.py`

- `AgeEstimate` (dataclass) : `age: int`, `sexe: str | None`
  (« Homme »/« Femme », informatif — stocké dans `results_json` seulement).
- `AgeEstimator` (ABC) : `async estimate(image_bytes: bytes) -> AgeEstimate`.
- `FaceppAgeEstimator` (name `facepp`) :
  - `POST https://api-us.faceplusplus.com/facepp/v3/detect`, form
    `api_key`, `api_secret`, `return_attributes=age,gender`, fichier
    `image_file`. Endpoint surchargable par `FACEPP_DETECT_ENDPOINT`.
  - Réutilise `downscale_for_facepp` et `_raise_for_facepp_error` de
    `facepp.py` ; 1 retry sur timeout/erreur réseau/5xx (même politique,
    timeout 10 s).
  - `faces` vide → `NoFaceError` ; plusieurs visages → le plus grand
    (`face_rectangle` de plus grande aire — la validation qualité amont
    rejette déjà le multi-visages quand InsightFace est chargé).
  - Parse `faces[i].attributes.age.value` et `gender.value`
    (`Male`→« Homme », `Female`→« Femme »).
- `LocalAgeEstimator` (name `local`) : enveloppe
  `vision.analyze_demographics(raw)` — `ok=False` → `NoFaceError`, modèle non
  chargé (`RuntimeError`) → `EngineUnavailableError`.
- `async estimate_age(front_bytes, mode=None) -> tuple[AgeEstimate | None, str | None]`
  (résultat + nom du moteur utilisé) : même table de modes que le module peau
  (`facepp` → [facepp], `local` → [local], `auto` → [facepp, local], défaut
  env `ANALYSIS_ENGINE` sinon `facepp`). **Toute `SkinEngineError` est
  absorbée** (warning log) → `(None, None)` : l'échec de l'âge ne casse jamais
  l'analyse de peau (`"age": null`).

## Âge réel & message (fonctions pures dans `age.py`)

- `real_age_from_birth_date(birth_date: date, today: date | None = None) -> int`
  — âge révolu, anniversaire pris en compte.
- `skin_age_message_fr(delta: int) -> str` :

| delta | message |
|---|---|
| ≤ −3 | « Votre peau paraît {abs(delta)} ans plus jeune que votre âge ! » |
| −2 à 2 | « Votre peau correspond à votre âge. » |
| ≥ 3 | « Votre peau paraît {delta} ans de plus — voici des soins ciblés. » |

- Sans `birth_date` (pas de delta) : message
  « Votre peau paraît {estimated_age} ans (estimation). »
- L'estimation n'est **jamais** présentée comme exacte : le mot « estimation »
  figure dans la réponse API (`estimated_age` documenté comme estimation), le
  README et l'écran Flutter.

## Modèle de données (migration `scripts/migrate_age_columns.py`)

```sql
ALTER TABLE clients                ADD COLUMN IF NOT EXISTS birth_date DATE;
ALTER TABLE skin_analyses          ADD COLUMN IF NOT EXISTS estimated_age  INTEGER;
ALTER TABLE skin_analyses          ADD COLUMN IF NOT EXISTS real_age       INTEGER;
ALTER TABLE skin_analyses          ADD COLUMN IF NOT EXISTS skin_age_delta INTEGER;
ALTER TABLE condition_product_map  ADD COLUMN IF NOT EXISTS min_age INTEGER;
ALTER TABLE condition_product_map  ADD COLUMN IF NOT EXISTS max_age INTEGER;
```

Script idempotent (pattern `migrate_pharmacy_profile.py`) ; `models.py` mis à
jour en miroir (colonnes nullables — `create_all` couvre les bases neuves).

## Endpoints

- `POST /v1/clients` : champ optionnel `birth_date` (ISO `YYYY-MM-DD`).
  Validation Pydantic : âge résultant entre **13 et 110 ans**, sinon 422 avec
  message FR (« Date de naissance invalide : l'âge doit être entre 13 et
  110 ans. »).
- `PATCH /v1/clients/{id}` (nouveau) : mise à jour partielle
  (`prenom`, `nom`, `telephone`, `email`, `peau_sensible`, `birth_date`),
  mêmes validations, scopé pharmacie via le helper d'appartenance (404 sinon).
- `POST /v1/skin/analyze` (extension) :
  1. analyse peau inchangée ;
  2. estimation d'âge sur la photo `front` **déjà en mémoire** (aucun appel
     photo supplémentaire côté client) ;
  3. `real_age` si `client_id` fourni **et** `client.birth_date` renseignée ;
  4. `skin_age_delta = estimated_age − real_age` si les deux existent ;
  5. persistance des 3 colonnes + `age_engine`/`sexe_estime` dans
     `results_json` ;
  6. bloc `age` dans la réponse.

Réponse (ajout au contrat existant) :

```json
{
  "age": {
    "estimated_age": 32,
    "real_age": 28,
    "skin_age_delta": 4,
    "message_fr": "Votre peau paraît 4 ans de plus — voici des soins ciblés."
  }
}
```

`real_age`/`skin_age_delta` nullables ; `age: null` si les deux moteurs
échouent (la réponse peau reste complète).

## Recommandations (extension `recommend.py`)

- `fetch_mappings` renvoie aussi `min_age`/`max_age`.
- `build_recommendations(scores, skin_type, mappings, products, age=None,
  skin_age_delta=None)` :
  - `age` = `real_age` si disponible, sinon `estimated_age`, sinon `None`
    (calculé par l'appelant) ;
  - filtre par ligne : `min_age`/`max_age` NULL = passe ; sinon
    `min_age ≤ age ≤ max_age` ; **`age` None ⇒ filtres d'âge ignorés** ;
  - règle anti-âge (codée) : `wrinkles` ne déclenche des recommandations que
    si `score ≥ 40` **ou** `age ≥ 35` **ou** `age` inconnu — le seuil global
    de 30 reste la porte d'entrée ;
  - boost : si `skin_age_delta ≥ 3`, contributions des conditions `wrinkles`
    et `dark_spots` multipliées par `AGE_DELTA_BOOST = 1.5`.

## Frontend (Flutter)

- `skin_analysis.dart` : `AgeInfo{estimatedAge, realAge, skinAgeDelta,
  messageFr}` + `SkinAnalysisResult.age` nullable (`age` absent/null toléré).
- `client_profile.dart` + `client_repository.dart` : champ `birthDate`
  (`DateTime?`), envoyé en ISO à la création.
- `new_client_screen.dart` : champ « Date de naissance (optionnel) » avec
  `showDatePicker` (bornes 13–110 ans), format affiché `jj/mm/aaaa`.
- `skin_result_screen.dart` : carte « Âge de la peau » en tête quand
  `age != null` — `message_fr` en principal, sous-texte
  « Estimation : {estimated} ans » + « Âge réel : {real} ans » si présent.
- `AnalysisResult`/ancien flux : inchangés.

## Gestion des erreurs

| Cas | Comportement |
|---|---|
| Face++ Detect quota/timeout/réseau | retry puis repli selon mode ; échec total → `age: null` |
| Aucun visage détecté par l'estimateur | `age: null` (l'analyse peau, elle, a déjà validé la photo) |
| `birth_date` absente | `estimated_age` seul, message « (estimation) », filtres d'âge sur `estimated_age` |
| `birth_date` invalide (< 13 ou > 110 ans) | 422 FR à la création/PATCH client |
| `client_id` d'une autre pharmacie (PATCH) | 404 (isolation multi-tenant) |

## Tests

- `test_age_estimator.py` : parser Face++ detect (fixture JSON — visage
  unique, multi-visages → le plus grand, `faces` vide → `NoFaceError`,
  quota → `FaceppQuotaError`, API mockée via `_post`) ; `LocalAgeEstimator`
  (monkeypatch `vision.analyze_demographics`) ; `estimate_age` absorbe les
  erreurs → `(None, None)`.
- `test_age_logic.py` : `real_age_from_birth_date` (avant/après
  anniversaire) ; bandes de `skin_age_message_fr` (−3, −2, 0, 2, 3).
- `test_recommend.py` (extension) : filtre `min_age`/`max_age` (borné,
  NULL, age None) ; règle anti-âge (score 35 + age 30 → exclu ; score 45 +
  age 30 → inclus ; score 35 + age 40 → inclus ; age None → inclus) ; boost
  delta ≥ 3 sur le rang.
- `test_skin_endpoint.py` (extension) : bloc `age` complet quand l'estimateur
  (mocké) répond + `birth_date` en base ; `age: null` quand l'estimateur
  échoue ; colonnes persistées ; création client avec `birth_date` invalide →
  422 ; PATCH client d'une autre pharmacie → 404.
- Flutter : `skin_analysis_test.dart` étendu (bloc `age` présent et absent).

## Points d'attention

- L'appel Face++ Detect ajoute ~1 appel API par analyse (5 au total avec les
  4 skinanalyze) — quota gratuit à surveiller.
- `estimate_age` est appelé **après** le succès de l'analyse peau : pas de
  coût si la requête échoue avant.
- Confidentialité inchangée : la photo n'est jamais stockée, seuls les
  résultats numériques (âges, delta) le sont.
