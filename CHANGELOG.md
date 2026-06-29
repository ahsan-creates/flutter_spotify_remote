## 0.0.3

* Bundled `SpotifyiOS.xcframework` (v5.0.1) directly — no Podfile `source` required in consuming apps
* Fixed `initiateSession` build error caused by new required `campaign` parameter in SDK v5.0.1
* Added `initializeSession()` — configures `SPTSessionManager` with backend `tokenSwapURL` and
  `tokenRefreshURL` so the iOS SDK performs silent token refresh automatically (~every 55 min),
  with no app-switch after the first user approval
* Added `renewSession()` — manually triggers a silent backend refresh at any time
* Added `source` field to `SpotifyAccessTokenEvent` (`'firstAuth'` / `'silentRefresh'` /
  `'directAuth'`) so callers can distinguish how each token was obtained
* iOS: `SPTSessionManagerDelegate` fires `SpotifyAccessTokenEvent` on both first auth and every
  automatic renewal; `SPTAppRemote` is reconnected automatically after silent refresh

## 0.0.2

* iOS improvements and bug fixes

## 0.0.1

* Initial release
* iOS support via Spotify iOS SDK v5.0.1 (CocoaPods — no bundled xcframework)
* Android support via Spotify Android App Remote SDK (.aar)
* Playback control: play, pause, resume, skip next/previous, seek, shuffle, repeat
* Real-time `Stream<SpotifyEvent>` for player state and connection changes
* `SpotifyAccessTokenEvent` for Flutter-side token persistence (iOS)
* Typed exceptions: `SpotifyNotInstalledException`, `SpotifyAuthException`,
  `SpotifyConnectionException`, `SpotifyCommandException`
