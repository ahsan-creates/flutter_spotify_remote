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

/// Thrown when a Spotify Web API request fails for an unmapped reason.
///
/// Volume control goes through the Spotify Web API — the App Remote SDK has no
/// volume endpoint on either platform — so these errors surface from
/// [FlutterSpotifyRemote.setVolume] and friends.
class SpotifyWebApiException implements Exception {
  /// HTTP status code returned by `api.spotify.com`.
  final int statusCode;

  /// Human-readable description, taken from the API error body when present.
  final String message;

  SpotifyWebApiException(this.statusCode, this.message);

  @override
  String toString() => 'Spotify Web API error $statusCode: $message';
}

/// Thrown when a volume change is rejected because the account is not Premium.
///
/// Spotify restricts `PUT /me/player/volume` to Premium subscribers; Free
/// accounts get HTTP 403 no matter which device is active.
class SpotifyPremiumRequiredException implements Exception {
  /// Human-readable description.
  final String message;

  SpotifyPremiumRequiredException([
    this.message = 'Spotify Premium is required to control volume.',
  ]);

  @override
  String toString() => message;
}

/// Thrown when there is no active Spotify device to apply the volume to.
///
/// Spotify only accepts a volume change for a device that is currently
/// playing or was recently active. Start playback (or pass an explicit
/// `deviceId`) before changing the volume.
class SpotifyNoActiveDeviceException implements Exception {
  /// Human-readable description.
  final String message;

  SpotifyNoActiveDeviceException([
    this.message = 'No active Spotify device. Start playback first.',
  ]);

  @override
  String toString() => message;
}
