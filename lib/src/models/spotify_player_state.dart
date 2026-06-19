import 'spotify_track.dart';

/// Repeat mode values matching the native SDK.
enum SpotifyRepeatMode {
  /// Repeat is disabled.
  off,

  /// Repeat the current track.
  track,

  /// Repeat the current context (playlist / album).
  context,
}

/// Snapshot of the Spotify player at a point in time.
class SpotifyPlayerState {
  /// Currently playing track.
  final SpotifyTrack track;

  /// Whether playback is paused.
  final bool isPaused;

  /// Current playback position in milliseconds.
  final int playbackPosition;

  /// Whether shuffle is active.
  final bool isShuffling;

  /// Current repeat mode.
  final SpotifyRepeatMode repeatMode;

  const SpotifyPlayerState({
    required this.track,
    required this.isPaused,
    required this.playbackPosition,
    required this.isShuffling,
    required this.repeatMode,
  });

  /// Deserialize from a native platform map.
  factory SpotifyPlayerState.fromMap(Map<String, dynamic> map) =>
      SpotifyPlayerState(
        track: SpotifyTrack.fromMap(map),
        isPaused: map['isPaused'] as bool? ?? true,
        playbackPosition: map['playbackPosition'] as int? ?? 0,
        isShuffling: map['isShuffling'] as bool? ?? false,
        repeatMode: SpotifyRepeatMode.values[
            (map['repeatMode'] as int? ?? 0)
                .clamp(0, SpotifyRepeatMode.values.length - 1)],
      );
}
