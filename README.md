# flutter_spotify_remote

[![pub package](https://img.shields.io/pub/v/flutter_spotify_remote.svg)](https://pub.dev/packages/flutter_spotify_remote)
[![pub points](https://img.shields.io/pub/points/flutter_spotify_remote)](https://pub.dev/packages/flutter_spotify_remote/score)
[![platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-blue.svg)](https://pub.dev/packages/flutter_spotify_remote)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Control the Spotify app from Flutter. `flutter_spotify_remote` wraps the official
**Spotify App Remote SDK** on both platforms and gives you one Dart API for
playback commands, a real-time player-state stream, and OAuth with silent token
refresh.

```dart
await FlutterSpotifyRemote.instance.play('spotify:track:6rqhFgbbKwnb9MLmUQDhG6');
```

---

## Features

- 🎛 **Playback control** — play, pause, resume, skip, seek, shuffle, repeat
- 📡 **Real-time state** — a `Stream<SpotifyEvent>` of player state and connection changes
- 🔐 **OAuth with silent refresh** — backend token swap/refresh on **both** iOS and Android, so users approve once and never app-switch again
- 🧩 **Sealed event hierarchy** — handle every `SpotifyEvent` exhaustively with `switch`
- 🚨 **Typed exceptions** — `SpotifyNotInstalledException`, `SpotifyAuthException`, and friends
- 📦 **iOS framework bundled** — `SpotifyiOS.xcframework` ships with the plugin; no extra Podfile `source` needed

## Platform support

| Platform | Supported | Min version | Underlying SDK                             |
|----------|-----------|-------------|--------------------------------------------|
| Android  | ✅        | API 21      | Spotify Android App Remote SDK (`.aar`)    |
| iOS      | ✅        | iOS 14      | SpotifyiOS 5.0.1 (xcframework, bundled)    |

The Spotify app must be installed and logged in on the device — this plugin
remote-controls it, it does not stream audio itself.

---

## Installation

```yaml
dependencies:
  flutter_spotify_remote: ^0.0.4
```

Then register your app in the
[Spotify Developer Dashboard](https://developer.spotify.com/dashboard) to get a
**client ID**, and add your redirect URI (e.g. `yourapp://callback`) there.

---

## iOS setup

### 1. Install pods

The `SpotifyiOS.xcframework` is vendored by the plugin's podspec, so a plain
`pod install` is all that is required:

```bash
cd ios && pod install
```

### 2. Register the redirect URI scheme

In **ios/Runner/Info.plist**, declare the scheme half of your redirect URI and
allow querying the Spotify app:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>spotify</string>
</array>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>yourapp</string>
    </array>
  </dict>
</array>
```

The redirect callback is forwarded automatically through Flutter's plugin
registrar — no `AppDelegate` changes are needed.

---

## Android setup

The Spotify Android App Remote SDK `.aar` cannot be redistributed via Maven and
must be added to your app manually.

### 1. Download the SDK

Grab `spotify-app-remote-release-*.aar` from the
[Spotify Android SDK releases](https://github.com/spotify/android-sdk/releases).

### 2. Place the `.aar` in your app

```
android/
  app/
    libs/
      spotify-app-remote-release-0.8.0.aar
```

### 3. Reference it in `android/app/build.gradle(.kts)`

```kotlin
dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
```

### 4. Add the internet permission

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 5. Declare the redirect URI placeholders

Authorization runs through the Spotify auth library, which registers a redirect
receiver activity built from two manifest placeholders. **The manifest merge
fails without them.** Set both to match your `redirectUrl` — for
`yourapp://callback` that is scheme `yourapp`, host `callback`:

```kotlin
android {
    defaultConfig {
        manifestPlaceholders["redirectSchemeName"] = "yourapp"
        manifestPlaceholders["redirectHostName"] = "callback"
    }
}
```

Package visibility (`<queries>` for `com.spotify.music`, required on Android 11+)
is contributed by the plugin, so no host-app entry is needed.

---

## Quick start

```dart
import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';

final spotify = FlutterSpotifyRemote.instance;

// 1. Listen for events *before* connecting
spotify.onEvent.listen((event) {
  switch (event) {
    case SpotifyPlayerStateChangedEvent(:final playerState):
      print('Now playing: ${playerState.track.name}');
    case SpotifyConnectionChangedEvent(:final status):
      print('Connection: $status');
    case SpotifyAccessTokenEvent(:final accessToken, :final expiresIn):
      prefs.setString('spotify_token', accessToken); // persist it
  }
});

// 2. Authorize (see "Authentication" below for the production path)
await spotify.connectAndAuthorize(
  clientId: 'YOUR_CLIENT_ID',
  redirectUrl: 'yourapp://callback',
);

// 3. Control playback
await spotify.play('spotify:track:6rqhFgbbKwnb9MLmUQDhG6');
await spotify.pause();
await spotify.resume();
await spotify.skipNext();
await spotify.skipPrevious();
await spotify.seekTo(30000);          // 30 seconds
await spotify.setShuffle(true);
await spotify.setRepeatMode(1);       // 0=off 1=track 2=context

await spotify.disconnect();
```

A complete runnable app lives in [`example/`](example).

---

## Authentication

### Recommended: `initializeSession` with a backend

Call `initializeSession()` on every app start with your token swap and refresh
endpoints. The native SDK then performs first-time OAuth, and refreshes the
token silently (~every 55 minutes) with **no further app-switch**:

```dart
await spotify.initializeSession(
  clientId: 'YOUR_CLIENT_ID',
  redirectUrl: 'yourapp://callback',
  tokenSwapURL: 'https://your-backend.example.com/swap',
  tokenRefreshURL: 'https://your-backend.example.com/refresh',
);

// Later, to force a refresh:
await spotify.renewSession();
```

Both endpoints take a form-encoded POST and return standard Spotify JSON
(`access_token`, `expires_in`, optional `refresh_token`):

| Endpoint          | Request body                                                       |
|-------------------|--------------------------------------------------------------------|
| `tokenSwapURL`    | `grant_type=authorization_code&code=…&redirect_uri=…`               |
| `tokenRefreshURL` | `grant_type=refresh_token&refresh_token=…`                          |

Your **client secret stays on the backend** — never ship it in the app.

Without a `tokenSwapURL`, Android falls back to the implicit grant:
`initializeSession` still emits an access token, but there is no refresh token,
so `renewSession()` fails with `NO_SESSION`.

### Silent reconnect on later launches

Persist the token from `SpotifyAccessTokenEvent` and reconnect without any
app-switch:

```dart
await spotify.connectWithToken(
  clientId: 'YOUR_CLIENT_ID',
  redirectUrl: 'yourapp://callback',
  accessToken: storedToken,
);
```

Tokens are **never stored natively** — persistence is yours to control, in
`SharedPreferences` or secure storage:

```dart
case SpotifyAccessTokenEvent(:final accessToken, :final expiresIn, :final source):
  await prefs.setString('spotify_token', accessToken);
  await prefs.setInt(
    'spotify_token_expires',
    DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
  );
```

`source` tells you how the token arrived: `firstAuth`, `silentRefresh`, or
`directAuth`.

---

## API reference

### `FlutterSpotifyRemote.instance`

| Method | Description |
|--------|-------------|
| `initializeSession(...)` | Configure OAuth with backend swap/refresh (recommended) |
| `renewSession()` | Force a silent token refresh |
| `connectAndAuthorize(...)` | OAuth app-switch without a backend |
| `connectWithToken(...)` | Silent connect using a stored token |
| `disconnect()` | Disconnect and release SDK resources |
| `isConnected()` | Whether the App Remote is connected |
| `getAccessToken()` | The current access token |
| `canPlayOnDemand()` | Whether the account may play an individual track URI |
| `play(uri)` | Play a Spotify URI |
| `pause()` / `resume()` | Pause / resume playback |
| `skipNext()` / `skipPrevious()` | Track navigation |
| `seekTo(ms)` | Seek within the current track |
| `setShuffle(bool)` | Enable/disable shuffle |
| `setRepeatMode(int)` | `0`=off, `1`=track, `2`=context |
| `onEvent` | `Stream<SpotifyEvent>` of all events |

### Events

| Event | Fields |
|-------|--------|
| `SpotifyPlayerStateChangedEvent` | `playerState` (`SpotifyPlayerState`) |
| `SpotifyConnectionChangedEvent` | `status`, `message?` |
| `SpotifyAccessTokenEvent` | `accessToken`, `expiresIn`, `source` |

### Exceptions

| Exception | When thrown |
|-----------|-------------|
| `SpotifyNotInstalledException` | Spotify is not installed |
| `SpotifyAuthException` | Token expired or auth failed |
| `SpotifyConnectionException` | Connection attempt failed |
| `SpotifyCommandException` | Playback command rejected by the SDK |

---

## Known limitations

- **Spotify must be installed** and logged in; this plugin does not stream audio.
- **Spotify Free accounts cannot play a single track URI** on demand — check
  `canPlayOnDemand()` and fall back to a playlist or album context.
- The **first authorization always app-switches** to Spotify. Every later launch
  is silent if you use `initializeSession` or a stored token.
- The Android `.aar` must be added manually — Spotify's terms prevent
  distribution through Maven Central.

---

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/ahsan-creates/flutter_spotify_remote). Please run
`flutter analyze` and `flutter test` before opening a PR.

## License

MIT — see [LICENSE](LICENSE).
