# 🦑 Calatube

Interface Spotify-like pour écouter YouTube **sans publicités**, avec vos playlists synchronisées et les métadonnées TheAudioDB.

## Fonctionnalités

- 🎵 **Recherche YouTube** affichée en mode Spotify (titre + artiste, pas de miniatures vidéo)
- 📚 **Bibliothèque** avec vos playlists YouTube synchronisées + playlists locales
- 🏠 **Accueil** : grille 4×2 (playlists + mix), carrousel de mix, tendances musicales FR
- 🖼️ **TheAudioDB** pour les pochettes et métadonnées de qualité
- 🚫 **Zéro publicité** via l'API Invidious (instances publiques)
- 🎛️ Mini-player flottant avec contrôles complets
- 🌑 Thème noir / gris foncé

## Installation Android

### Prérequis
- Flutter 3.x (`flutter --version`)
- Android Studio ou Android SDK
- Un appareil Android (API 23+) ou un émulateur

### Build APK

```bash
cd calatube
flutter pub get
flutter build apk --release
# APK dans : build/app/outputs/flutter-apk/app-release.apk
```

### Build APK debug (plus rapide pour tester)
```bash
flutter build apk --debug
```

## Configurer la connexion YouTube (optionnel)

Sans configuration, l'app fonctionne en mode invité : recherche et tendances disponibles.

Pour synchroniser vos playlists YouTube :

1. Rendez-vous sur [console.cloud.google.com](https://console.cloud.google.com)
2. Créez un projet → Activez **YouTube Data API v3**
3. Créez des identifiants OAuth 2.0 (type: Application Web)
4. Ajoutez `http://localhost/callback` comme URI de redirection
5. Ouvrez `lib/screens/login_screen.dart` et remplacez :
   ```dart
   static const _clientId = 'YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com';
   ```
   par votre Client ID

## Architecture

```
lib/
├── main.dart                    # Point d'entrée + providers
├── models/
│   └── track_model.dart         # TrackModel + PlaylistModel
├── services/
│   ├── youtube_service.dart     # API Invidious + YouTube Data API OAuth
│   ├── audiodb_service.dart     # TheAudioDB (pochettes, métadonnées)
│   ├── player_service.dart      # Lecteur audio
│   ├── audio_handler.dart       # audio_service (notification système)
│   └── playlist_service.dart   # Playlists locales + sync YT
├── screens/
│   ├── main_shell.dart          # Navigation principale
│   ├── home_tab.dart            # Accueil : grille + mix + tendances
│   ├── search_screen.dart       # Recherche style Spotify
│   ├── library_screen.dart      # Bibliothèque (YT + local)
│   ├── player_screen.dart       # Lecteur plein écran
│   ├── playlist_detail_screen.dart
│   ├── playlist_add_screen.dart
│   ├── login_screen.dart        # OAuth YouTube
│   └── settings_screen.dart
└── widgets/
    ├── squid_logo.dart          # Logo calamar blanc (CustomPainter)
    ├── mini_player.dart         # Mini-lecteur flottant
    └── track_tile.dart          # Ligne de piste style Spotify
```

## Technologies utilisées

| Composant | Solution |
|-----------|----------|
| Audio sans pub | [Invidious](https://invidious.io/) (API publique) |
| Playlists YT | YouTube Data API v3 (OAuth) |
| Métadonnées | [TheAudioDB](https://www.theaudiodb.com/) |
| Lecture audio | just_audio + audio_service |
| Cache images | cached_network_image |

## Notes légales

Calatube est un projet personnel à usage privé. Il utilise des APIs publiques selon leurs conditions d'utilisation.
