/// Thrown when the Spotify app is not installed on the device.
class SpotifyNotInstalledException implements Exception {
  /// Human-readable description.
  final String message = 'Spotify is not installed on this device.';

  @override
  String toString() => message;
}

/// Thrown when the SDK fails to connect or loses its connection.
class SpotifyConnectionException implements Exception {
  /// Platform error code (e.g. `CONNECTION_FAILED`).
  final String code;

  /// Human-readable description.
  final String message;

  SpotifyConnectionException(this.code, this.message);

  @override
  String toString() => '[$code] $message';
}

/// Thrown when authentication fails or the access token has expired.
class SpotifyAuthException implements Exception {
  /// Human-readable description.
  final String message;

  SpotifyAuthException(this.message);

  @override
  String toString() => message;
}

/// Thrown when a playback command (play, pause, seek, etc.) fails.
class SpotifyCommandException implements Exception {
  /// The method name that failed (e.g. `play`).
  final String command;

  /// Human-readable description.
  final String message;

  SpotifyCommandException(this.command, this.message);

  @override
  String toString() => 'Command [$command] failed: $message';
}
