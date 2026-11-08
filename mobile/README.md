# Hoop Archive — mobile

The Flutter client for Hoop Archive. See the [root README](../README.md) for the
full-stack overview, backend setup, and data/licensing notes.

## Run

```bash
flutter pub get
flutter run                                                   # iOS sim / localhost
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```

The API base URL defaults to `http://localhost:8000` (iOS simulator) or
`http://10.0.2.2:8000` (Android emulator). Override it for a physical device:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Tests & analysis

```bash
flutter test       # widget + unit tests
flutter analyze    # lints
```

## Structure

```
lib/
├── core/
│   ├── api/          ApiClient (Dio, cache-aware) + hand-written DTOs
│   ├── cache/        KeyValueStore + ResponseCache (offline caching)
│   ├── widgets/      shared widgets (OfflineBanner, CachedCopyNote)
│   ├── connectivity  online/offline provider (connectivity_plus)
│   ├── env           API base URL resolution (--dart-define overridable)
│   ├── router        GoRouter config (+ not-found page)
│   ├── theme         light/dark Material 3 theme
│   └── time_ago      relative-time labels
└── features/
    ├── home/         overview (counts, data source, roadmap)
    ├── players/      list + search/filter, profile, trend charts
    └── compare/      two-player comparison + picker sheet
```

### State & data

- **Riverpod** for state: `FutureProvider`s for one-shot reads (meta, filters,
  profile, comparison) and a `StateNotifier` for the paginated players list.
- **GoRouter** for navigation, including deep links like `/players/42` and
  `/compare?a=1&b=2`.
- **Offline-first:** `ApiClient` is wrapped by a `ResponseCache` that writes
  every successful response to a local document cache and replays it when a
  request fails. The store sits behind a `KeyValueStore` interface
  (`SharedPreferences` in the app, in-memory in tests), so the backing engine is
  swappable. No provider API keys ever live in the client — all third-party
  calls are proxied by the backend.
