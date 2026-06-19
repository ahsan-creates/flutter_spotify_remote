/// Represents the currently playing Spotify track.
class SpotifyTrack {
  /// Spotify URI, e.g. `spotify:track:6rqhFgbbKwnb9MLmUQDhG6`.
  final String uri;

  /// Display name of the track.
  final String name;

  /// Primary artist name.
  final String artistName;

  /// Album name.
  final String albumName;

  /// Opaque identifier used to fetch album art via the Spotify API.
  final String imageIdentifier;

  /// Total track duration in milliseconds.
  final int durationMs;

  const SpotifyTrack({
    required this.uri,
    required this.name,
    required this.artistName,
    required this.albumName,
    required this.imageIdentifier,
    required this.durationMs,
  });

  /// Deserialize from a native platform map.
  factory SpotifyTrack.fromMap(Map<String, dynamic> map) => SpotifyTrack(
        uri: map['trackUri'] as String? ?? '',
        name: map['trackName'] as String? ?? '',
        artistName: map['artistName'] as String? ?? '',
        albumName: map['albumName'] as String? ?? '',
        imageIdentifier: map['imageIdentifier'] as String? ?? '',
        durationMs: map['duration'] as int? ?? 0,
      );

  /// Serialize to a map for passing to native code.
  Map<String, dynamic> toMap() => {
        'trackUri': uri,
        'trackName': name,
        'artistName': artistName,
        'albumName': albumName,
        'imageIdentifier': imageIdentifier,
        'duration': durationMs,
      };
}
