import 'spotify_player_state.dart';
import 'spotify_connection_status.dart';

/// Base class for all events emitted by the Spotify App Remote SDK.
sealed class SpotifyEvent {
  const SpotifyEvent();
}

/// Fired whenever the player state changes (track, pause/resume, seek, etc.).
class SpotifyPlayerStateChangedEvent extends SpotifyEvent {
  /// The new player state.
  final SpotifyPlayerState playerState;

  const SpotifyPlayerStateChangedEvent(this.playerState);
}

/// Fired when the connection status changes.
class SpotifyConnectionChangedEvent extends SpotifyEvent {
  /// New connection status.
  final SpotifyConnectionStatus status;

  /// Optional human-readable message (e.g. error description).
  final String? message;

  const SpotifyConnectionChangedEvent(this.status, {this.message});
}

/// Fired on iOS after the OAuth app-switch returns a fresh access token.
///
/// Store [accessToken] in `SharedPreferences` and pass it to
/// [FlutterSpotifyRemote.connectWithToken] on subsequent launches to avoid
/// repeating the app-switch.
class SpotifyAccessTokenEvent extends SpotifyEvent {
  /// The OAuth access token.
  final String accessToken;

  /// Seconds until the token expires.
  final int expiresIn;

  /// How the token was obtained:
  /// - `'firstAuth'`     — full OAuth app-switch via [initializeSession]
  /// - `'silentRefresh'` — automatic backend refresh via [initializeSession] / [renewSession]
  /// - `'directAuth'`    — token returned by [connectAndAuthorize] URL callback
  final String source;

  const SpotifyAccessTokenEvent(
    this.accessToken,
    this.expiresIn, {
    this.source = 'directAuth',
  });
}
