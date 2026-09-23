# NoteCheck — Android app

Flutter client for the NoteCheck counterfeit-detection API.

## Features

- **Scan**: camera or gallery photo → auto-crop toggle → animated analysis → verdict screen with confidence ring, genuine/counterfeit probabilities, analysed-vs-original preview and latency.
- **History**: paged list with stored previews, genuine/fake filter, pull-to-refresh, swipe-to-delete, detail sheet.
- **Insights**: personal donut + stat tiles; administrators also get fleet totals, a 7/14/30-day stacked bar chart and recent scans across all users.
- **Users** (admin): search, promote/demote, delete.
- **Settings**: API server address with connection test, default auto-crop, dark/light/system theme, rename, change password, model card.
- Session token kept in the Android keystore; the app restores offline and re-validates when the server is reachable.

## Structure

```
lib/
├── main.dart                  providers + root routing (splash → login → home)
├── core/       theme.dart · api_client.dart · formatters.dart
├── models/     models.dart (User, Prediction, Scan, stats, health)
├── services/   session_store.dart (secure storage + prefs)
├── providers/  settings · auth · scan · admin   (ChangeNotifier + provider)
├── screens/    splash · auth · home · scan · history · insights · settings
└── widgets/    common.dart (cards, gauges, scanner overlay…) · scan_tile.dart
```

## Run

```bash
flutter pub get
flutter run                      # debug on a connected device/emulator
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Default API address is `http://10.0.2.2:8000` (host machine from the Android emulator). Change it from the sign-in screen's status chip or in *Settings → API server*.

## Test

```bash
flutter analyze
flutter test
```

Widget tests run the whole app against an in-memory fake server (`test/widget_test.dart`).

## Release signing

`android/app/build.gradle.kts` signs release builds with the debug key so `flutter build apk --release` works out of the box. Before publishing, create a keystore and `android/key.properties` (both git-ignored) and switch the `release` signing config.

## Icons

`assets/icon/` holds the source artwork; regenerate launcher icons with `dart run flutter_launcher_icons`.
