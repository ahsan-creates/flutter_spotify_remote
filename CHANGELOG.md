## 0.0.5

**Volume control.** The App Remote SDK exposes no volume API on either platform,
so this is implemented over the Spotify Web API (`PUT /me/player/volume`).

* Added `setVolume(percent)` and `getVolume()` — `0`–`100`, clamped, with an
  optional `deviceId`
* Added `volumeUp()` / `volumeDown()` with a configurable `step` (default 10),
  and `mute()` / `unmute()` / `toggleMute()` that restore the pre-mute level
* Added `isMuted` and `lastKnownVolume` for rendering UI without a network call
* `setVolume` coalesces rapid calls — one request in flight at a time, last
  value wins — so it is safe to call per frame from a slider's `onChanged`
* Access tokens from `connectWithToken` and `SpotifyAccessTokenEvent` are now
  cached and reused for the Web API; `setAccessToken()` supplies one manually
* Added `SpotifyPremiumRequiredException` (403), `SpotifyNoActiveDeviceException`
  (404 / no active device) and `SpotifyWebApiException` for other failures
* `disconnect()` now clears the cached token and volume state
* Example app: volume slider, mute toggle and step button

Volume requires Spotify Premium, an active device, and the
`user-modify-playback-state` / `user-read-playback-state` scopes — see the
Volume section of the README.

## 0.0.4

**Android auth parity.** Android now implements the full session/token contract
that previously existed only on iOS.

* Android: implemented `initializeSession()` / `renewSession()` — previously
  `notImplemented`, so Android never obtained a token
* Android: `getAccessToken()` now returns the live token instead of a
  `NOT_SUPPORTED` error, and the `accessToken` event is emitted with the same
  `source` values as iOS (`firstAuth` / `silentRefresh`)
* Android: OAuth via the Spotify auth library (`com.spotify.android:auth`), with
  backend token swap and refresh when `tokenSwapURL` / `tokenRefreshURL` are set
* Android: `connectWithToken()` now reuses the supplied token with
  `showAuthView(false)` instead of running an interactive connect, so silent
  reconnects no longer app-switch into Spotify
* Android: declared `<queries>` for `com.spotify.music` — Android 11+ package
  visibility made `connect()` fail with `CouldNotFindSpotifyApp` even when
  Spotify was installed
* Android: `SPOTIFY_NOT_INSTALLED` / `TOKEN_EXPIRED` error codes and the
  `disconnected` event now match the iOS contract; `spotifyUri` is honoured on
  connect
* Android setup now requires the `redirectSchemeName` / `redirectHostName`
  manifest placeholders — see README
* Added `canPlayOnDemand()` — reports whether the connected account may play an
  individual track URI (Spotify Free accounts cannot), so callers can adapt the
  UI instead of letting `play()` fail
* iOS: unchanged

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
