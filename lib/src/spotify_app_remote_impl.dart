import 'dart:async';

import 'spotify_app_remote_platform.dart';
import 'spotify_app_remote_method_channel.dart';
import 'spotify_volume_controller.dart';
import 'models/spotify_event.dart';
import 'exceptions/spotify_exceptions.dart';

/// Main entry point for the Spotify App Remote plugin.
///
/// Use [FlutterSpotifyRemote.instance] to access the singleton.
///
/// ### Typical usage
/// ```dart
/// // First launch — triggers the Spotify app-switch for OAuth
/// await FlutterSpotifyRemote.instance.connectAndAuthorize(
///   clientId: 'YOUR_CLIENT_ID',
///   redirectUrl: 'yourapp://callback',
/// );
///
/// // Subsequent launches — use the stored token (no app-switch)
/// await FlutterSpotifyRemote.instance.connectWithToken(
///   clientId: 'YOUR_CLIENT_ID',
///   redirectUrl: 'yourapp://callback',
///   accessToken: storedToken,
/// );
///
/// // Listen for events
/// FlutterSpotifyRemote.instance.onEvent.listen((event) {
///   if (event is SpotifyPlayerStateChangedEvent) {
///     print(event.playerState.track.name);
///   }
/// });
///
/// // Volume (Spotify Premium only — see setVolume)
/// await FlutterSpotifyRemote.instance.setVolume(40);
/// ```
class FlutterSpotifyRemote {
  FlutterSpotifyRemote._();

  /// The singleton instance.
  static final FlutterSpotifyRemote instance = FlutterSpotifyRemote._();

  final SpotifyAppRemotePlatform _platform = MethodChannelSpotifyAppRemote();

  late final SpotifyVolumeController _volume = SpotifyVolumeController(
    tokenProvider: _resolveAccessToken,
  );

  String? _cachedToken;
  StreamSubscription<SpotifyEvent>? _tokenCapture;

  /// Broadcast stream of all Spotify events.
  ///
  /// See [SpotifyEvent] subclasses for available event types.
  Stream<SpotifyEvent> get onEvent => _platform.onEvent;

  /// Initialize a Spotify session with backend token swap and silent refresh.
  ///
  /// The recommended auth path for production apps. Call on every app start —
  /// the iOS SDK will handle first-time OAuth, silent background refresh, and
  /// everything in between without further input.
  ///
  /// - [tokenSwapURL]    — your backend endpoint that exchanges the auth code
  ///   for an access + refresh token pair (form-encoded POST, field: `code`)
  /// - [tokenRefreshURL] — your backend endpoint that returns a new access
  ///   token given a refresh token (form-encoded POST, field: `refresh_token`)
  ///
  /// Listen to [onEvent] for [SpotifyAccessTokenEvent] to persist the token.
  /// After receiving the token, call [connectWithToken] to connect the player.
  Future<void> initializeSession({
    required String clientId,
    required String redirectUrl,
    required String tokenSwapURL,
    required String tokenRefreshURL,
    List<String> scopes = const [
      'app-remote-control',
      'user-modify-playback-state',
      'user-read-playback-state',
      'user-library-read',
      'playlist-read-private',
      'streaming',
    ],
    String spotifyUri = '',
    bool clientOnly = false,
  }) {
    _captureTokens();
    return _platform.initializeSession(
      clientId: clientId,
      redirectUrl: redirectUrl,
      tokenSwapURL: tokenSwapURL,
      tokenRefreshURL: tokenRefreshURL,
      scopes: scopes,
      spotifyUri: spotifyUri,
      clientOnly: clientOnly,
    );
  }

  /// Connect using a previously stored access token (silent, no app-switch).
  Future<void> connectWithToken({
    required String clientId,
    required String redirectUrl,
    required String accessToken,
    String spotifyUri = '',
  }) {
    _cachedToken = accessToken;
    _captureTokens();
    return _platform.connectWithToken(
      clientId: clientId,
      redirectUrl: redirectUrl,
      accessToken: accessToken,
      spotifyUri: spotifyUri,
    );
  }

  /// Trigger the OAuth app-switch to Spotify (first-time authentication).
  Future<void> connectAndAuthorize({
    required String clientId,
    required String redirectUrl,
    String spotifyUri = '',
  }) {
    _captureTokens();
    return _platform.connectAndAuthorize(
      clientId: clientId,
      redirectUrl: redirectUrl,
      spotifyUri: spotifyUri,
    );
  }

  /// Silently renew the Spotify access token via the backend tokenRefreshURL.
  ///
  /// The new token is emitted as a [SpotifyAccessTokenEvent] on [onEvent].
  /// Throws [SpotifyAuthException] if no stored Keychain session is found.
  /// Silently refresh the Spotify access token using the backend tokenRefreshURL.
  ///
  /// Call [initializeSession] first — the native side reuses the stored URLs
  /// and scopes. The new token is emitted as [SpotifyAccessTokenEvent].
  Future<void> renewSession() => _platform.renewSession();

  /// Disconnect from Spotify App Remote and release resources.
  ///
  /// Also clears the cached access token and volume state.
  Future<void> disconnect() {
    _tokenCapture?.cancel();
    _tokenCapture = null;
    _cachedToken = null;
    _volume.reset();
    return _platform.disconnect();
  }

  /// Returns `true` if currently connected to the Spotify app.
  Future<bool> isConnected() => _platform.isConnected();

  /// Returns the current OAuth access token (iOS only while connected).
  Future<String> getAccessToken() async {
    final token = await _platform.getAccessToken();
    if (token.isNotEmpty) _cachedToken = token;
    return token;
  }

  /// Whether the connected user may play a specific track on demand.
  ///
  /// Spotify Free accounts return false: they can play a playlist or album
  /// context (shuffled) but not an individual track URI. Use this to pick the
  /// right UI rather than letting [play] fail.
  Future<bool> canPlayOnDemand() => _platform.canPlayOnDemand();

  /// Start playing the given Spotify URI.
  Future<void> play(String spotifyUri) => _platform.play(spotifyUri);

  /// Pause playback.
  Future<void> pause() => _platform.pause();

  /// Resume paused playback.
  Future<void> resume() => _platform.resume();

  /// Skip to the next track.
  Future<void> skipNext() => _platform.skipNext();

  /// Skip to the previous track.
  Future<void> skipPrevious() => _platform.skipPrevious();

  /// Seek to [positionMs] milliseconds from the start of the current track.
  Future<void> seekTo(int positionMs) => _platform.seekTo(positionMs);

  /// Enable or disable shuffle.
  Future<void> setShuffle(bool enabled) => _platform.setShuffle(enabled);

  /// Set repeat mode: `0` = off, `1` = track, `2` = context.
  Future<void> setRepeatMode(int mode) => _platform.setRepeatMode(mode);

  // ── Access token cache ─────────────────────────────────────────

  /// Supplies the token the volume methods authorize their Web API calls with.
  ///
  /// Every token the plugin sees is cached, so this normally resolves without
  /// a platform call. [getAccessToken] is the last resort and is iOS-only.
  Future<String> _resolveAccessToken() async {
    final cached = _cachedToken;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final token = await _platform.getAccessToken();
      if (token.isNotEmpty) _cachedToken = token;
      return token;
    } on SpotifyAuthException {
      rethrow;
    } catch (_) {
      // Android has no getAccessToken — the caller must supply one.
      return '';
    }
  }

  /// Caches tokens delivered on the event stream (iOS OAuth and silent refresh).
  void _captureTokens() {
    _tokenCapture ??= _platform.onEvent.listen(
      (event) {
        if (event is SpotifyAccessTokenEvent) {
          _cachedToken = event.accessToken;
        }
      },
      // A dead event channel must not break playback commands.
      onError: (_) {},
    );
  }

  /// Stores the OAuth [accessToken] used by the volume methods.
  ///
  /// Only needed on Android, or when restoring a token from storage without
  /// going through [connectWithToken] — tokens from [connectWithToken] and
  /// from [SpotifyAccessTokenEvent] are cached automatically. Pass an empty
  /// string to clear it.
  void setAccessToken(String accessToken) => _cachedToken = accessToken;

  // ── Volume ────────────────────────────────────────────────────────

  /// Sets the Spotify volume to [percent] (`0`–`100`, values outside are clamped).
  ///
  /// The App Remote SDK has no volume API on either platform, so this goes
  /// through the Spotify Web API (`PUT /me/player/volume`) against the
  /// account's active device. That means it needs:
  ///
  /// - **Spotify Premium** — Free accounts get
  ///   [SpotifyPremiumRequiredException]
  /// - the `user-modify-playback-state` and `user-read-playback-state` scopes
  ///   (both included in the default scopes of [initializeSession])
  /// - an **active device** — start playback first, or pass [deviceId];
  ///   otherwise [SpotifyNoActiveDeviceException] is thrown
  /// - a valid access token — see [setAccessToken] on Android
  ///
  /// Safe to drive straight from a slider: rapid calls are coalesced into one
  /// request at a time, last value wins.
  ///
  /// Throws [SpotifyAuthException] if the token expired — call [renewSession].
  Future<void> setVolume(int percent, {String? deviceId}) {
    _captureTokens();
    return _volume.setVolume(percent, deviceId: deviceId);
  }

  /// Reads the active device's current volume as `0`–`100`.
  ///
  /// Throws [SpotifyNoActiveDeviceException] when nothing is playing.
  /// See [setVolume] for the full list of requirements.
  Future<int> getVolume() {
    _captureTokens();
    return _volume.getVolume();
  }

  /// Raises the volume by [step] percentage points (default 10), capped at 100.
  Future<void> volumeUp({int step = 10, String? deviceId}) {
    _captureTokens();
    return _volume.volumeUp(step: step, deviceId: deviceId);
  }

  /// Lowers the volume by [step] percentage points (default 10), floored at 0.
  Future<void> volumeDown({int step = 10, String? deviceId}) {
    _captureTokens();
    return _volume.volumeDown(step: step, deviceId: deviceId);
  }

  /// Silences playback, remembering the current volume for [unmute].
  Future<void> mute({String? deviceId}) {
    _captureTokens();
    return _volume.mute(deviceId: deviceId);
  }

  /// Restores the volume captured by [mute]. Does nothing when not muted.
  Future<void> unmute({String? deviceId}) {
    _captureTokens();
    return _volume.unmute(deviceId: deviceId);
  }

  /// [mute]s when audible, [unmute]s when muted.
  Future<void> toggleMute({String? deviceId}) {
    _captureTokens();
    return _volume.toggleMute(deviceId: deviceId);
  }

  /// Whether the volume was muted through [mute] and not yet restored.
  bool get isMuted => _volume.isMuted;

  /// The most recent volume set or read, without a network call.
  ///
  /// `null` until [setVolume] or [getVolume] has succeeded once. Useful to
  /// seed a slider without an extra Web API round-trip.
  int? get lastKnownVolume => _volume.lastKnownVolume;
}
