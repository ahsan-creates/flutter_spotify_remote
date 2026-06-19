## 0.0.1

* Initial release
* iOS support via Spotify iOS SDK v5.0.1 (CocoaPods — no bundled xcframework)
* Android support via Spotify Android App Remote SDK (.aar)
* Playback control: play, pause, resume, skip next/previous, seek, shuffle, repeat
* Real-time `Stream<SpotifyEvent>` for player state and connection changes
* `SpotifyAccessTokenEvent` for Flutter-side token persistence (iOS)
* Typed exceptions: `SpotifyNotInstalledException`, `SpotifyAuthException`,
  `SpotifyConnectionException`, `SpotifyCommandException`
