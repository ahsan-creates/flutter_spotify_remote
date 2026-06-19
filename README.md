# flutter_spotify_remote

[![pub.dev](https://img.shields.io/pub/v/flutter_spotify_remote.svg)](https://pub.dev/packages/flutter_spotify_remote)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A Flutter plugin for the **Spotify App Remote SDK**. Control Spotify playback,
subscribe to real-time player state, and manage OAuth authentication on iOS and
Android — all without bundling any xcframework.

---

## Features

- Connect to the Spotify app silently (stored token) or via OAuth app-switch
- Play, pause, resume, skip, seek, shuffle, and set repeat mode
- Real-time `Stream<SpotifyEvent>` for player state and connection changes
- iOS access token forwarded to Flutter for `SharedPreferences` persistence
- Typed exceptions: `SpotifyNotInstalledException`, `SpotifyAuthException`, etc.
- Sealed `SpotifyEvent` hierarchy — exhaustively handled with `switch`

## Platform support

| Platform | Supported | SDK version                          |
|----------|-----------|--------------------------------------|
| iOS      | ✅        | SpotifyiOS 5.0.1 (CocoaPods)        |
| Android  | ✅        | Spotify Android App Remote SDK       |

---

## Installation

```yaml
dependencies:
  flutter_spotify_remote: ^0.0.1
```

---

## iOS setup

### 1. Add the CocoaPods dependency

The plugin pulls `SpotifyiOS` automatically via CocoaPods. Run:

```bash
cd ios && pod install
```

### 2. Register the redirect URI scheme

In your **Runner/Info.plist** add a URL scheme matching your redirect URI
(e.g. `spotifyappremote`):

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>spotify</string>
</array>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>$(BUNDLE_ID)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>spotifyappremote</string>
    </array>
  </dict>
</array>
```

### 3. Forward the redirect URL

In **AppDelegate.swift** override `application(_:open:options:)` — Flutter's
plugin registrar handles this automatically via `addApplicationDelegate`, so no
manual wiring is needed in the default Flutter `AppDelegate`.

---

## Android setup

The Spotify Android App Remote SDK `.aar` cannot be distributed via Maven and
must be downloaded manually.

### 1. Download the SDK

Download `spotify-app-remote-release-*.aar` from the
[Spotify Android SDK releases](https://github.com/spotify/android-sdk/releases)
page.

### 2. Place the .aar in your app

Copy it to your **app's** `android/app/libs/` directory (create it if needed):

```
android/
  app/
    libs/
      spotify-app-remote-release-0.8.0.aar
```

### 3. Reference it in `android/app/build.gradle` (or `.kts`)

```kotlin
dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
```

### 4. Add required permissions to `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

---

## Quick start

```dart
import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';

final spotify = FlutterSpotifyRemote.instance;

// Listen for events before connecting
spotify.onEvent.listen((event) {
  switch (event) {
    case SpotifyPlayerStateChangedEvent(:final playerState):
      print('Now playing: ${playerState.track.name}');
    case SpotifyConnectionChangedEvent(:final status):
      print('Connection: $status');
    case SpotifyAccessTokenEvent(:final accessToken, :final expiresIn):
      // Persist for next launch
      prefs.setString('spotify_token', accessToken);
  }
});

// First launch — triggers Spotify app-switch for OAuth
await spotify.connectAndAuthorize(
  clientId: 'YOUR_CLIENT_ID',
  redirectUrl: 'yourapp://callback',
);

// Subsequent launches — silent connect (no app-switch)
await spotify.connectWithToken(
  clientId: 'YOUR_CLIENT_ID',
  redirectUrl: 'yourapp://callback',
  accessToken: storedToken,
);

// Playback control
await spotify.play('spotify:track:6rqhFgbbKwnb9MLmUQDhG6');
await spotify.pause();
await spotify.resume();
await spotify.skipNext();
await spotify.skipPrevious();
await spotify.seekTo(30000);          // 30 seconds
await spotify.setShuffle(true);
await spotify.setRepeatMode(1);       // 0=off 1=track 2=context

// Disconnect when done
await spotify.disconnect();
```

---

## Token storage

Tokens are **never stored natively**. On iOS, after the OAuth app-switch
completes, a `SpotifyAccessTokenEvent` is emitted on the `onEvent` stream.
Persist it in `SharedPreferences` (or secure storage) on the Dart side:

```dart
case SpotifyAccessTokenEvent(:final accessToken, :final expiresIn):
  await prefs.setString('spotify_token', accessToken);
  await prefs.setInt(
    'spotify_token_expires',
    DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
  );
```

On the next launch, pass the stored token to `connectWithToken` to skip the
app-switch entirely.

---

## API reference

### `FlutterSpotifyRemote.instance`

| Method | Description |
|--------|-------------|
| `connectWithToken(...)` | Silent connect using stored token |
| `connectAndAuthorize(...)` | OAuth app-switch (first launch) |
| `disconnect()` | Disconnect and release SDK resources |
| `isConnected()` | Returns `true` if connected |
| `getAccessToken()` | Current token (iOS only, while connected) |
| `play(uri)` | Play a Spotify URI |
| `pause()` | Pause playback |
| `resume()` | Resume playback |
| `skipNext()` | Skip to next track |
| `skipPrevious()` | Skip to previous track |
| `seekTo(ms)` | Seek to position in milliseconds |
| `setShuffle(bool)` | Enable/disable shuffle |
| `setRepeatMode(int)` | `0`=off, `1`=track, `2`=context |
| `onEvent` | `Stream<SpotifyEvent>` of all events |

### Events

| Event | Fields |
|-------|--------|
| `SpotifyPlayerStateChangedEvent` | `playerState` (`SpotifyPlayerState`) |
| `SpotifyConnectionChangedEvent` | `status`, `message?` |
| `SpotifyAccessTokenEvent` | `accessToken`, `expiresIn` |

### Exceptions

| Exception | When thrown |
|-----------|-------------|
| `SpotifyNotInstalledException` | Spotify is not installed |
| `SpotifyAuthException` | Token expired or auth failed |
| `SpotifyConnectionException` | Connection attempt failed |
| `SpotifyCommandException` | Playback command rejected by SDK |

---

## Known limitations

- **Spotify must be installed** on the device; streaming is not supported.
- **iOS first launch requires an app-switch** to Spotify for OAuth. Subsequent
  launches using a stored token are silent.
- `getAccessToken()` is **not available on Android** (the Android App Remote
  SDK does not expose the token).
- The Android `.aar` must be added manually (cannot be on Maven Central per
  Spotify's terms).

---

## License

MIT — see [LICENSE](LICENSE).
