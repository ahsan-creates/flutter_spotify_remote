# flutter_spotify_remote example

A runnable demo of [`flutter_spotify_remote`](https://pub.dev/packages/flutter_spotify_remote):
connect to the Spotify app, control playback, and follow the player state stream.

## Running it

1. Register an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
   and add `spotifyappremote://callback` as a redirect URI.
2. Put your client ID in [`lib/main.dart`](lib/main.dart).
3. Follow the Android `.aar` setup in the [plugin README](../README.md#android-setup).
4. Install the Spotify app on the device and log in.

```bash
flutter run
```
