# Frontend Flutter — MVP analyse faciale (âge & sexe)

App mobile du projet. Rôle actuel : guider l'utilisateur pour capturer **4 vues**
du visage (face, profil gauche 45°, profil droit 45°, dessus/cheveux), puis envoyer
la **vue de face** au backend FastAPI qui renvoie le **sexe** et l'**âge estimé**.

## Structure

```
frontend/
├── pubspec.yaml
├── lib/
│   ├── main.dart                     # Accueil → capture → résultat
│   ├── capture/                      # Capture guidée (vos fichiers existants)
│   │   ├── capture_pose.dart         #   définition des 4 poses
│   │   ├── face_pose_validator.dart  #   validation de la pose (ML Kit)
│   │   ├── guidance_overlay.dart     #   cadre de guidage
│   │   └── pose_capture_screen.dart  #   écran de capture
│   ├── services/
│   │   └── analysis_api.dart         # client HTTP vers /v1/analyze
│   └── screens/
│       └── result_screen.dart        # affichage sexe + âge
```

## Mise en route

Les dossiers de plateforme (`android/`, `ios/`, …) ne sont **pas** versionnés.
Générez-les une fois, puis lancez l'app :

```bash
cd frontend
flutter create .          # génère android/, ios/, etc. sans toucher à lib/
flutter pub get
flutter run
```

> `flutter create .` ne modifie ni `lib/`, ni `pubspec.yaml` s'ils existent déjà ;
> il ne fait qu'ajouter les dossiers de plateforme manquants.

## Permissions caméra (à ajouter après `flutter create .`)

### Android — `android/app/src/main/AndroidManifest.xml`

Ajoutez, juste avant `<application>` :

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```

Dans `android/app/build.gradle`, assurez `minSdkVersion 21` (requis par `camera`/ML Kit) :

```gradle
defaultConfig {
    minSdkVersion 21
}
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>L'application a besoin de la caméra pour capturer votre visage.</string>
```

## Adresse du backend (important)

Réglez `baseUrl` dans `lib/services/analysis_api.dart` selon la cible :

| Cible                | baseUrl                         |
|----------------------|---------------------------------|
| Émulateur Android    | `http://10.0.2.2:8000` (défaut) |
| Simulateur iOS       | `http://localhost:8000`         |
| Appareil physique    | `http://<IP-locale-du-PC>:8000` |

Le backend doit tourner (`uvicorn app.main:app --port 8000`) et être accessible
depuis l'appareil (même réseau Wi-Fi pour un téléphone physique).
```
