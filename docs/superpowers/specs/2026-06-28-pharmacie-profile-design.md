# Profil pharmacie — intégration complète (édition + logo)

## Contexte

L'onglet "Profil" de l'app Lumina (`frontend/lib/screens/home_screen.dart`,
`_ProfilTab`) est aujourd'hui une carte en lecture seule : logo générique +
nom de la pharmacie + bouton de déconnexion. Le modèle backend `Pharmacy`
(`backend/app/models.py`) ne porte que `nom`, `email`, `password_hash`,
`created_at`. Il n'existe :

- aucun champ de contact (téléphone, adresse) ni description ;
- aucun stockage/upload d'image (le `/v1/analyze` lit une image mais ne la
  conserve jamais) ;
- aucun endpoint de mise à jour de la pharmacie.

La session stockée côté frontend (`AuthSession`) ne retient que
`token`, `pharmacyId`, `pharmacyNom`.

Ce cycle ajoute un **profil pharmacie complet** : le pharmacien remplit et
met à jour ses informations (nom, téléphone, adresse, ville, description) et
téléverse son **logo**. La fiche technique des clients (édition/suppression
d'historique) fait l'objet d'un spec séparé, traité juste après celui-ci.

## Objectifs

- Le pharmacien peut consulter, remplir et modifier : nom, téléphone, adresse,
  ville, description.
- Le pharmacien peut ajouter / remplacer / supprimer son logo.
- Les informations et le logo **persistent** (survivent à un redémarrage de
  l'app et du backend).
- L'onglet Profil adopte le langage visuel Lumina (cohérent avec le reste).
- Le badge "nom de pharmacie" du Home reflète immédiatement un changement de
  nom.

## Hors périmètre

- Changement d'email de connexion ou de mot de passe (confirmé avec
  l'utilisateur).
- Fiche technique client (édition/suppression d'historique) — spec séparé,
  prochain cycle.
- Multi-utilisateurs / rôles par pharmacie.

## Décisions

- **Email = lecture seule.** L'email est l'identifiant de connexion ; affiché
  mais non modifiable ici.
- **Nom = éditable** (champ existant, naturellement inclus dans le formulaire
  bien que non recoché explicitement).
- **Logo stocké en octets dans la base** (`logo_bytes` + `logo_mime`), pas sur
  disque. Pour un unique petit logo par pharmacie c'est plus simple et plus
  robuste : pas de dossier d'upload, pas de configuration de fichiers
  statiques, pas de fichiers orphelins, sauvegarde atomique avec la ligne. La
  taille reste petite côté client (redimensionnement + qualité via
  `image_picker`) et plafonnée côté serveur (≤ 2 Mo).

## Backend

### Modèle `Pharmacy` — nouvelles colonnes (toutes nullables)

| Colonne       | Type             | Rôle                                     |
|---------------|------------------|------------------------------------------|
| `telephone`   | String           | Téléphone de contact                     |
| `adresse`     | String           | Adresse (rue)                            |
| `ville`       | String           | Ville                                    |
| `description` | String           | Slogan / phrase libre                    |
| `logo_bytes`  | LargeBinary      | Octets du logo (NULL si absent)          |
| `logo_mime`   | String           | Type MIME du logo (ex. `image/png`)      |
| `updated_at`  | DateTime (tz)    | Horodatage de dernière modif (cache-bust)|

### Migration

L'app utilise `Base.metadata.create_all`, qui crée les tables manquantes mais
**n'ajoute pas** de colonnes à une table existante. On ajoute un script
idempotent `backend/scripts/migrate_pharmacy_profile.py` exécutant des
`ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS ...` (Postgres). Exécuté une
fois avant de lancer la version mise à jour.

### Schémas Pydantic

- **`PharmacyOut`** étendu : `id`, `nom`, `email`, `telephone`, `adresse`,
  `ville`, `description`, `has_logo: bool` (dérivé de `logo_bytes is not None`),
  `updated_at: datetime | None`.
- **`PharmacyUpdate`** (nouveau) : `nom`, `telephone`, `adresse`, `ville`,
  `description` — tous optionnels. Seuls les champs fournis sont mis à jour.

### Endpoints (JWT, scopés à la pharmacie du token)

| Méthode | Route                | Effet                                              |
|---------|----------------------|----------------------------------------------------|
| PATCH   | `/v1/pharmacy`       | Met à jour les champs texte ; renvoie `PharmacyOut`|
| POST    | `/v1/pharmacy/logo`  | Multipart image → valide type/taille, stocke octets+mime, bump `updated_at` ; renvoie `PharmacyOut` |
| GET     | `/v1/pharmacy/logo`  | Renvoie les octets du logo avec le bon `Content-Type` (404 si absent) |
| DELETE  | `/v1/pharmacy/logo`  | Efface `logo_bytes`/`logo_mime` ; renvoie `PharmacyOut` |

Validation upload : `Content-Type` dans {jpeg, png, webp}, taille ≤ 2 Mo
(réutilise les constantes existantes de `main.py`). `PATCH` met aussi
`updated_at = now()`.

`GET /v1/auth/me` renvoie désormais le `PharmacyOut` étendu (sert de
"get profile").

## Frontend

### Dépendance

- Ajout de `image_picker` (galerie/appareil photo) dans `pubspec.yaml`, utilisé
  avec `maxWidth ~800`, `imageQuality ~85` pour garder l'upload léger.

### Données / état

- **`PharmacyProfile`** (nouveau modèle) : champs de `PharmacyOut`.
- **`PharmacyApi`** (nouveau service) : `getProfile()`, `updateProfile(...)`,
  `uploadLogo(bytes, mime)`, `deleteLogo()` — tous avec l'en-tête
  `Authorization: Bearer`.
- **`pharmacyProfileProvider`** (Riverpod, AsyncNotifier) : charge le profil,
  expose update/upload/delete. Après une modif réussie, met aussi à jour
  `AuthSession.pharmacyNom` (donc le badge Home se rafraîchit). Cela implique
  d'ajouter au `AuthNotifier` une petite méthode `updatePharmacyNom(String)`
  qui réécrit aussi le `nom` dans le stockage sécurisé.

### Écrans

- **`_ProfilTab` redessiné** (look Lumina) :
  - Carte héro : **logo** circulaire (tap → choisir/téléverser ; petit badge
    appareil photo ; repli sur un monogramme dégradé si pas de logo), nom,
    description, email.
  - Lignes d'info : téléphone / adresse / ville (icône + valeur, ou "Ajouter").
  - Bouton **"Modifier le profil"** → écran d'édition dédié.
  - Bouton de déconnexion conservé.
- **`PharmacyProfileEditScreen`** (nouveau) : champs `LuminaUi` (nom,
  téléphone, adresse, ville, description) + bouton dégradé d'enregistrement.
  Sauvegarde → `PATCH /v1/pharmacy` → met à jour le provider + le nom de
  session → pop.

### Affichage du logo

`Image.network('$baseUrl/v1/pharmacy/logo?v=$updatedAt', headers: {auth})`.
Le `?v=` (basé sur `updated_at`) force le rechargement après remplacement.
Repli (`errorBuilder`) sur le monogramme.

## Flux de données

1. Ouverture de l'onglet Profil → `getProfile()` (GET `/v1/auth/me` étendu) →
   affichage.
2. Édition → `PATCH /v1/pharmacy` → renvoie le profil à jour → MAJ provider +
   nom de session.
3. Logo → `image_picker` → `POST /v1/pharmacy/logo` (multipart) → renvoie le
   profil (`has_logo=true`, nouveau `updated_at`) → rafraîchissement de l'image.

## Gestion des erreurs

- Erreurs réseau → SnackBar (réutilise le motif d'exception existant des
  dépôts).
- Erreurs de validation upload (type/taille) → SnackBar explicite.
- Échec de chargement du logo → monogramme de repli.

## Tests

- `flutter analyze` reste propre (la barre du projet).
- Backend : vérification manuelle par `curl` (PATCH, upload/serve/delete du
  logo), avec le compte de test `test@lumina.com` / `lumina123`.
- Manuel sur device : modifier les champs, téléverser un logo, confirmer que
  les deux persistent après redémarrage de l'app.

## Risques / hypothèses

- La migration `ADD COLUMN IF NOT EXISTS` suppose Postgres (cas du projet).
- `image_picker` requiert les permissions Android caméra/galerie ; à vérifier
  dans le manifeste lors de l'implémentation.
- Le logo en base reste petit grâce au redimensionnement client ; le plafond
  serveur (2 Mo) est un garde-fou, pas la voie normale.
