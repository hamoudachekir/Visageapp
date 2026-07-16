# Client onboarding flow — design spec

**Date** : 2026-06-20
**Statut** : Approuvé par l'utilisateur en conversation, implémentation en cours.

## Contexte

Suite au pivot vers "Atena" (thème clair "Clinical Spa", Riverpod, GoRouter — cf.
décisions précédentes), l'utilisateur a fourni des captures d'écran de référence
montrant le parcours attendu entre l'accueil et la capture photo :

```
Accueil → [modale] Choisissez le type de session
              ├─ Nouveau Client → Formulaire profil → Questionnaire (3 Q) → Capture
              └─ Client existant → Recherche par téléphone → Questionnaire (3 Q) → Capture
```

Décision prise en cours de route : renommage de la marque "Atena" → **"Parapharmacie"**
(nom générique en attendant un nom de marque définitif), car chaque pharmacie aura
à terme son propre compte (login/signup par pharmacie — hors scope ici, noté pour
plus tard).

## Scope

**Inclus :**
- Renommage "Atena" → "Parapharmacie" (splash, titre de l'app, logo de l'accueil).
- Restylage de l'écran d'accueil vers le thème clair "Clinical Spa" (actuellement
  encore sur le thème sombre "Ismouda").
- Modale de choix du type de session.
- Écran "Nouveau Client" (formulaire profil).
- Écran "Client existant" (recherche par téléphone).
- Écran "Questionnaire" (3 questions fixes, telles que dans les captures).
- Extension du widget `AppHeader` (titre + flèche retour + actions, pour les
  sous-écrans).

**Exclus (hors scope, décidé explicitement) :**
- Tout backend de persistance. Les profils clients et réponses au questionnaire
  restent **en mémoire uniquement** (perdus à la fermeture de l'app), derrière une
  interface `ClientRepository` qui sera la seule chose à changer le jour où le
  backend Postgres existe.
- Login/signup par pharmacie.
- Les icônes panier/grille/liste/recherche visibles dans les captures de référence
  (YAGNI — aucune fonctionnalité associée n'existe encore).
- Les icônes (ⓘ)/(💡) par question du questionnaire (aucun contenu d'aide défini).
- Renommage du package Flutter / `applicationId` Android (`analyse_faciale` reste
  inchangé — changement plus risqué, à part).

**Prochain sous-projet (pas celui-ci)** : backend Postgres pour les tables
opérationnelles (`parapharmacies`, `clients`, `sessions`/`questionnaire_responses`).
Le `plan.docx` du projet prévoit déjà PostgreSQL + pgvector pour le catalogue
produits (section 3.5/3.6) — les nouvelles tables rejoignent la même base, sans
vecteur. Point de vigilance RGPD (plan §8.2) à traiter dans ce sous-projet : la
table `clients` est une nouvelle persistance de données personnelles qui n'existe
pas aujourd'hui.

## Architecture

**État partagé (Riverpod)** : un `SessionFlowNotifier` (provider `sessionFlowProvider`)
accumule `ClientProfile?` et `QuestionnaireAnswers?` au fil du parcours, pour que les
écrans suivants (et plus tard les résultats/recommandations) puissent les lire sans
les faire transiter manuellement de constructeur en constructeur. L'index de la
question courante dans le questionnaire reste un état local (`StatefulWidget`) —
rien d'autre n'en a besoin.

**Navigation** : `Navigator.push`/`MaterialPageRoute`, comme le parcours de capture
existant (Capture → Validation → Analyse → Résultat). Pas de nouvelles routes
GoRouter — GoRouter reste responsable uniquement de la coquille `/` → `/home`.

**Accès aux données client** : interface `ClientRepository` (`findByPhone`, `save`),
implémentation unique `InMemoryClientRepository`. C'est le seul point de couture
pour le futur backend.

## Écrans

1. **Accueil** (restylé) : carte logo "Parapharmacie" + slogan + bouton "Démarrer
   une nouvelle analyse" → ouvre la modale de choix de session. Pied de page
   statique "Connectée · En ligne · 97%" (déjà décidé précédemment, fidélité visuelle).
2. **Modale "Choisissez le type de session"** : `showDialog` (pas une route),
   deux choix tactiles "Nouveau Client" / "Client existant".
3. **Nouveau Client** : Prénom*, Nom*, Téléphone*, Email (optionnel), "Peau
   sensible ?" (menu déroulant Oui/Non/Je ne sais pas) → bouton "Démarrer le
   diagnostique" → Questionnaire.
4. **Client existant** : champ téléphone + bouton "Rechercher". Trouvé → direct au
   Questionnaire avec le profil pré-rempli. Pas trouvé → message inline + lien vers
   le formulaire Nouveau Client (téléphone pré-rempli).
5. **Questionnaire** : 3 questions fixes (type de peau / tendance acnéique /
   sensibilité cutanée), barre de progression, sélection unique, navigation
   Précédent/Suivant, le bouton de la 3e question devient "Commencer l'analyse de
   peau" → entre dans le `CaptureFlow` existant (inchangé).

## Gestion des erreurs & tests

- Validation de formulaire inline (réutilise le pattern `CustomTextField` existant).
- "Client non trouvé" est un état normal de l'UI, pas une erreur.
- Aucun appel réseau dans ce lot de travail → pas de gestion d'erreur réseau à
  ajouter ici.
- `flutter analyze` doit rester propre ; vérification manuelle du parcours complet
  sur le téléphone physique une fois implémenté.
