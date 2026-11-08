# Qalam Muslim

Qalam Muslim is an open-source Islamic companion application for Android, built with Flutter.

## Features

- Quran reading, recitations, multiple Qira'at, bookmarks, and tafsir.
- Hadith collections, search, grading, and explanations.
- Daily azkar, supplications, and the 99 Names of Allah.
- Prayer times, Adhan, reminders, Qibla direction, and prayer tracking.
- Local Arabic voice features and source-grounded Islamic reference search.
- Arabic and English interfaces, RTL/LTR layouts, themes, and offline resources.

## Open-source status and attribution

The application is published with its source code for public inspection and development. This codebase incorporates and adapts an existing MIT-licensed open-source Islamic companion project. The upstream copyright and MIT permission notice are retained in [LICENSE](LICENSE); third-party assets and libraries retain their own notices in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the accompanying license files.

Source repository: https://github.com/vhcjhyy-ctrl/Aya

## Build

Requirements: Flutter 3.44.x, Dart 3.10.x, and Android SDK.

```bash
flutter pub get
flutter build apk --flavor fdroid --release --target-platform android-arm64
```

The Android application ID is `com.ahmed.qalammuslim`.

## License

The main source is distributed under the MIT License, subject to the retained copyright and permission notices. Third-party components, datasets, and model weights may have separate terms; review the notices before redistributing them.
