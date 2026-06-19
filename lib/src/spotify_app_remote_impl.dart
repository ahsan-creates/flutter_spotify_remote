import 'spotify_app_remote_platform.dart';
import 'spotify_app_remote_method_channel.dart';
import 'models/spotify_event.dart';

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
/// ```
class FlutterSpotifyRemote {
  FlutterSpotifyRemote._();

  /// The singleton instance.
  static final FlutterSpotifyRemote instance = FlutterSpotifyRemote._();

  final SpotifyAppRemotePlatform _platform = MethodChannelSpotifyAppRemote();

  /// Broadcast stream of all Spotify events.
  ///
  /// See [SpotifyEvent] subclasses for available event types.
  Stream<SpotifyEvent> get onEvent => _platform.onEvent;

  /// Connect using a previously stored access token (silent, no app-switch).
  Future<void> connectWithToken({
    required String clientId,
    required String redirectUrl,
    required String accessToken,
    String spotifyUri = '',
  }) =>
      _platform.connectWithToken(
        clientId: clientId,
        redirectUrl: redirectUrl,
        accessToken: accessToken,
        spotifyUri: spotifyUri,
      );

  /// Trigger the OAuth app-switch to Spotify (first-time authentication).
  Future<void> connectAndAuthorize({
    required String clientId,
    required String redirectUrl,
    String spotifyUri = '',
  }) =>
      _platform.connectAndAuthorize(
        clientId: clientId,
        redirectUrl: redirectUrl,
        spotifyUri: spotifyUri,
      );

  /// Disconnect from Spotify App Remote and release resources.
  Future<void> disconnect() => _platform.disconnect();

  /// Returns `true` if currently connected to the Spotify app.
  Future<bool> isConnected() => _platform.isConnected();

  /// Returns the current OAuth access token (iOS only while connected).
  Future<String> getAccessToken() => _platform.getAccessToken();

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
}
