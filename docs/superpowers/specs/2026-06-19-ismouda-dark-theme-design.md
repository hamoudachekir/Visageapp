# Ismouda Dark Theme — Phase 1 (visual redesign)

## Context

The Claude Design project "Ismouda – Assistant d'analyse de peau"
(`https://claude.ai/design/p/479bb525-83dd-47ee-ac14-28273c1ca9f3`, file
`Ismouda Dark AI.dc.html`) contains a 9-screen mockup for a pharmacy-facing
skin-analysis product: Accueil, choix de session, création profil, recherche
client, questionnaire, capture photo, validation des photos, analyse en
cours, résultat/diagnostic.

The current Flutter app (`frontend/`) is a much smaller MVP: Home → 4-pose
guided capture (face, profil gauche, profil droit, dessus) → single backend
call (`POST /v1/analyze`, returns estimated age + sexe + confidence) →
simple result screen. There is no client database, no questionnaire, and no
product catalog/recommendation engine on the backend.

Building the full 9-screen product would require new backend functionality
(client profiles, questionnaire persistence, product matching) that doesn't
exist yet. This phase covers **only the visual redesign of the existing
flow**, plus two new screens that are pure UI (no new data dependencies):
photo validation and an analysis-progress screen. Client profiles,
questionnaire, session choice, and product recommendations are explicitly
out of scope for this phase and would each need their own spec.

## Goals

- Restyle Home and the capture flow to match the Ismouda dark visual
  language (gradients, glassmorphism, Plus Jakarta Sans / JetBrains Mono).
- Add a photo-validation screen (review the 4 captured shots, retake
  individually) between capture and analysis.
- Add a dedicated analyzing screen (progress ring + step checklist) instead
  of the current inline loading state.
- Restyle the result screen to match, keeping its existing content (no
  product recommendations).
- Zero changes to backend, camera/face-detection logic, or the NV21
  conversion fix already in place.

## Non-goals

- Client profile creation/search, session choice screen, skin questionnaire,
  product catalog/recommendations — each is a separate future phase with its
  own backend work.
- Any real sensor data (lux/brightness) or device status (battery, network)
  — the mockup's footer status bar and lux indicator are decorative chrome
  not backed by real data, so they are dropped rather than faked.

## Shared theme — `lib/theme/ismouda_theme.dart`

New file providing:

- **Colors**: background `#0B0D14` → `#13152150` → `#0C0E16` gradient,
  primary gradient `#8B6CFF` → `#6E7BFF`, accent purple `#9098FF`, success
  green `#1F9D57`/`#2BC974`, error red `#D14B4B`, text tones `#ECEEF8`
  (primary), `#9DA3BA` (secondary), `#8C92A8`/`#737A92` (muted).
- **Fonts**: `google_fonts` package, `Plus Jakarta Sans` (weights 400–800)
  for body/headings, `JetBrains Mono` for the small step-counter labels.
- **`IsmoudaBackground`**: a `Container` + `Stack` reproducing the radial
  gradient blobs and rotated rounded-square accent shapes from the mockup,
  used as the base of every screen.
- **`IsmoudaLogo`**: the rotated gradient diamond mark with the white
  highlight line, reused in headers and the home hero.
- **`IsmoudaHeader`**: app bar replacement — logo + "Ismouda" wordmark on the
  left, hardcoded "Pharmacie Kalai" / "Main Branch" text block on the right
  (static placeholder; no auth backend exists yet).
- **`PrimaryGradientButton`**: full-width rounded button with the primary
  gradient, used for all main CTAs.

## Screens

### 1. Home (`lib/main.dart` `HomeScreen`, restyled in place)

`IsmoudaBackground` + `IsmoudaHeader` + centered hero: glowing circle behind
the `IsmoudaLogo`, headline "L'assistant d'analyse de peau", subtitle,
`PrimaryGradientButton` "Démarrer une nouvelle analyse", caption "Analyse
guidée · résultat en ~60 secondes". Same single action (push into the
capture flow) as today — no new navigation here.

### 2. Capture (`lib/capture/pose_capture_screen.dart`, restyle only)

**No changes** to `CameraController` setup, `_processFrame`, the YUV420→NV21
conversion, or `FacePoseValidator` — this is a pure visual pass over the
existing widget tree.

- Replace `GuidanceOverlay`'s full oval ring with green/red **corner
  brackets** around the guide rect (matching the mockup's bracket style),
  plus a status pill centered just below the frame ("Visage détecté" /
  current hint) replacing the separate top instruction banner.
- Top bar: close (back) button + step pill ("1/4 · Vue de face") in
  `JetBrains Mono`. No lux/brightness indicator (no real sensor — see
  Non-goals).
- Thumbnail strip becomes **4 fixed slots** (Face, Profil G., Profil D.,
  Dessus) always visible, each showing a checkmark badge once captured
  instead of the current "only show what's captured" list.
- Capture button restyled as a white-ring circular button (gradient fill
  when `_conforme`), same enable/disable logic as today.
- Remove the manual "validate" checkmark icon button. When `_capture()`
  completes the 4th pose (`_allCaptured` becomes true), automatically
  navigate to the new Validation screen instead of waiting for a manual tap.

### 3. Validation (new — `lib/capture/photo_validation_screen.dart`)

`IsmoudaHeader` + "Validez vos photos" + subtitle + 2×2 grid of the 4
shots (`Image.file`), each with a small "Reprendre" pill button overlaid at
the bottom. Tapping "Reprendre" pushes back into `PoseCaptureScreen` in a
**single-pose retake mode**: the screen accepts an optional
`retakePose`/`existingShots` pair, jumps straight to that pose's camera
step, and on capture pops back to Validation with the updated shot list
(rather than calling `onCompleted` again). Bottom CTA "Démarrer l'analyse"
(`PrimaryGradientButton`) navigates to Analyzing with the final 4 shots.

### 4. Analyzing (new — `lib/screens/analyzing_screen.dart`)

`IsmoudaHeader` + circular progress ring (indeterminate — the backend
returns one response, not incremental progress) + 3-item step checklist:
"Photos importées" (checked immediately on entry), "Détection du visage"
(active while the `POST /v1/analyze` call is in flight), "Diagnostic"
(checked on success). *Renamed from the mockup's "Diagnostic &
recommandations" — no recommendations in this phase.* This screen owns the
`AnalysisApi().analyzeFace(...)` call (replacing the inline `_analyzing`
boolean currently in `CaptureFlow`): on success it replaces itself with
`ResultScreen`; on failure it shows the existing inline error state inline
(same copy/behavior as today, just restyled) with a retry that pops back to
Validation.

### 5. Result (`lib/screens/result_screen.dart`, restyle only)

Same fields as today (`sexe`, `ageEstime`, `confiance`), `IsmoudaBackground`
+ `IsmoudaHeader`, info rows restyled as glass cards matching the mockup's
dark card style, `PrimaryGradientButton`-style retry action. No product
recommendation section.

## Navigation summary

```
HomeScreen
  → PoseCaptureScreen (4 poses; auto-advances on completion)
    → PhotoValidationScreen (shots)
        ↔ PoseCaptureScreen (single-pose retake, returns shots)
        → AnalyzingScreen (shots)
            → ResultScreen (success)
            → (error state, retry → back to PhotoValidationScreen)
```

## Testing

- `flutter analyze` must stay clean (already the bar for this codebase).
- Manual verification on the physical Redmi device already wired up for
  this project (`flutter run -d <device-id>`): walk the full flow once
  (capture 4 poses → validate → retake one → analyze → result) and confirm
  no regressions in face detection / NV21 handling, since that code is
  untouched but its surrounding UI changes.
- No new automated widget tests planned for this phase — the existing
  `test/widget_test.dart` (currently a stale Counter-app template test) is
  out of scope to fix here; flag to the user separately if it should be
  updated/removed.

## Open assumptions to confirm during implementation review

- Dropping the lux/brightness pill and the connectivity/battery footer
  (confirmed with the user during brainstorming).
- Renaming the 3rd analyzing-step label to drop "& recommandations"
  (no recommendations exist yet).
- "Pharmacie Kalai" / "Main Branch" header text is hardcoded static text,
  not wired to any account system.
