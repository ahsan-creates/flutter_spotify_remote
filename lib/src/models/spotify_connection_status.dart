/// Connection state reported by the Spotify App Remote SDK.
enum SpotifyConnectionStatus {
  /// Successfully connected to the Spotify app.
  connected,

  /// Disconnected from the Spotify app.
  disconnected,

  /// Connection attempt failed for a non-auth reason.
  failed,

  /// The access token has expired; re-authenticate.
  tokenExpired,

  /// Spotify is not installed on this device.
  notInstalled,
}
