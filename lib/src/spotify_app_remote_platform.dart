import 'dart:async';
import 'models/spotify_event.dart';

/// Abstract interface that platform implementations must satisfy.
///
/// End users interact with [SpotifyAppRemote] instead of this class directly.
abstract class SpotifyAppRemotePlatform {
  // ── Auth & Connection ──────────────────────────────────────────────────

  /// Connect using a previously stored access token (silent, no app-switch).
  ///
  /// Prefer this path on every app launch after the first successful
  /// [connectAndAuthorize]. Store the token received via [SpotifyAccessTokenEvent]
  /// in `SharedPreferences` and pass it here.
  Future<void> connectWithToken({
    required String clientId,
    required String redirectUrl,
    required String accessToken,
    String spotifyUri = '',
  });

  /// Trigger the OAuth app-switch to Spotify (first-time authentication).
  ///
  /// On iOS this opens the Spotify app; the result is delivered via
  /// [SpotifyAccessTokenEvent] on the [onEvent] stream.
  /// On Android the SDK handles auth internally.
  Future<void> connectAndAuthorize({
    required String clientId,
    required String redirectUrl,
    String spotifyUri = '',
  });

  /// Disconnect from Spotify App Remote and release resources.
  Future<void> disconnect();

  /// Returns `true` if currently connected to the Spotify app.
  Future<bool> isConnected();

  /// Returns the current OAuth access token.
  ///
  /// Only available while connected. Throws [SpotifyAuthException] otherwise.
  /// Not supported on Android (throws [SpotifyCommandException]).
  Future<String> getAccessToken();

  // ── Playback ───────────────────────────────────────────────────────────

  /// Start playing the given Spotify URI (track, album, playlist, etc.).
  Future<void> play(String spotifyUri);

  /// Pause playback.
  Future<void> pause();

  /// Resume paused playback.
  Future<void> resume();

  /// Skip to the next track.
  Future<void> skipNext();

  /// Skip to the previous track.
  Future<void> skipPrevious();

  /// Seek to [positionMs] milliseconds from the start of the current track.
  Future<void> seekTo(int positionMs);

  /// Enable or disable shuffle.
  Future<void> setShuffle(bool enabled);

  /// Set repeat mode: `0` = off, `1` = track, `2` = context.
  Future<void> setRepeatMode(int mode);

  // ── Events ─────────────────────────────────────────────────────────────

  /// Broadcast stream of all Spotify events:
  ///
  /// - [SpotifyPlayerStateChangedEvent] — player state updated
  /// - [SpotifyConnectionChangedEvent] — connection status changed
  /// - [SpotifyAccessTokenEvent] — new token after iOS app-switch
  Stream<SpotifyEvent> get onEvent;
}
