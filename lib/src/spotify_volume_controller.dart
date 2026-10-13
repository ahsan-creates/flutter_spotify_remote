import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'exceptions/spotify_exceptions.dart';

/// Minimal HTTP response shape used by [SpotifyVolumeController].
///
/// Exists so tests can inject a fake sender without pulling an HTTP package
/// into the plugin's dependency graph.
class SpotifyHttpResponse {
  /// HTTP status code.
  final int statusCode;

  /// Raw response body (may be empty for `204 No Content`).
  final String body;

  const SpotifyHttpResponse(this.statusCode, this.body);
}

/// Sends a request to the Spotify Web API and returns the raw response.
typedef SpotifyHttpSender = Future<SpotifyHttpResponse> Function(
  String method,
  Uri url,
  Map<String, String> headers,
);

/// Volume control for the Spotify player, backed by the Spotify Web API.
///
/// The App Remote SDK exposes no volume API on iOS or Android, so volume is
/// changed through `PUT /me/player/volume` on the account's active device.
/// This means volume control needs a Premium account, the
/// `user-modify-playback-state` and `user-read-playback-state` scopes, and an
/// active device — see [FlutterSpotifyRemote.setVolume].
///
/// Used internally by [FlutterSpotifyRemote]; you normally call the volume
/// methods on that class rather than constructing this directly.
class SpotifyVolumeController {
  /// Creates a controller that authorizes with the token from [tokenProvider].
  ///
  /// [send] defaults to a `dart:io` HTTP client and is only overridden in tests.
  SpotifyVolumeController({
    required Future<String> Function() tokenProvider,
    SpotifyHttpSender? send,
  })  : _token = tokenProvider,
        _send = send ?? _defaultSend;

  static const _base = 'https://api.spotify.com/v1/me/player';

  final Future<String> Function() _token;
  final SpotifyHttpSender _send;

  int? _lastKnownVolume;
  int? _volumeBeforeMute;

  int? _desired;
  String? _desiredDeviceId;
  Future<void>? _draining;

  /// The most recent volume this controller applied or read, if any.
  ///
  /// Populated by [setVolume] and [getVolume]; `null` until one of them runs.
  /// Cheap to read — it never hits the network.
  int? get lastKnownVolume => _lastKnownVolume;

  /// Whether the volume was muted through [mute] and not yet restored.
  bool get isMuted => _volumeBeforeMute != null;

  /// Sets the Spotify volume to [percent] (`0`–`100`, clamped).
  ///
  /// Rapid calls — a UI slider being dragged — are coalesced: only one request
  /// is in flight at a time and intermediate values are dropped, so the last
  /// value always wins without hitting Spotify's rate limit.
  Future<void> setVolume(int percent, {String? deviceId}) {
    _desired = percent.clamp(0, 100);
    _desiredDeviceId = deviceId;
    return _drain();
  }

  /// Reads the current volume of the active device, as `0`–`100`.
  ///
  /// Throws [SpotifyNoActiveDeviceException] when nothing is playing.
  Future<int> getVolume() async {
    final res = await _request('GET', Uri.parse(_base));

    // 204 means the account has no active device at all.
    if (res.statusCode == 204 || res.body.isEmpty) {
      throw SpotifyNoActiveDeviceException();
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final device = body['device'] as Map<String, dynamic>?;
    final volume = device?['volume_percent'] as int?;

    if (volume == null) {
      throw SpotifyWebApiException(
        res.statusCode,
        'Active device does not report a volume.',
      );
    }

    _lastKnownVolume = volume;
    return volume;
  }

  /// Raises the volume by [step] percentage points, clamped to `100`.
  Future<void> volumeUp({int step = 10, String? deviceId}) async =>
      setVolume(await _currentVolume() + step, deviceId: deviceId);

  /// Lowers the volume by [step] percentage points, clamped to `0`.
  Future<void> volumeDown({int step = 10, String? deviceId}) async =>
      setVolume(await _currentVolume() - step, deviceId: deviceId);

  /// Silences playback, remembering the current volume for [unmute].
  ///
  /// Does nothing when already muted, so the remembered volume is never
  /// overwritten with `0`.
  Future<void> mute({String? deviceId}) async {
    if (isMuted) return;
    final current = await _currentVolume();
    await setVolume(0, deviceId: deviceId);
    _volumeBeforeMute = current;
  }

  /// Restores the volume captured by [mute].
  ///
  /// Does nothing when not muted.
  Future<void> unmute({String? deviceId}) async {
    final previous = _volumeBeforeMute;
    if (previous == null) return;
    await setVolume(previous, deviceId: deviceId);
    _volumeBeforeMute = null;
  }

  /// [mute]s when audible, [unmute]s when muted.
  Future<void> toggleMute({String? deviceId}) =>
      isMuted ? unmute(deviceId: deviceId) : mute(deviceId: deviceId);

  /// Drops the cached volume and mute state (called on disconnect).
  void reset() {
    _lastKnownVolume = null;
    _volumeBeforeMute = null;
    _desired = null;
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// The cached volume, falling back to a network read on first use.
  Future<int> _currentVolume() async => _lastKnownVolume ?? await getVolume();

  /// Serializes writes so a dragged slider issues one request at a time.
  Future<void> _drain() {
    final running = _draining;
    if (running != null) return running;

    final started = _loop();
    _draining = started;
    return started.whenComplete(() {
      if (identical(_draining, started)) _draining = null;
    });
  }

  Future<void> _loop() async {
    while (_desired != null) {
      final target = _desired!;
      final deviceId = _desiredDeviceId;
      _desired = null;

      final url = Uri.parse('$_base/volume').replace(queryParameters: {
        'volume_percent': '$target',
        if (deviceId != null) 'device_id': deviceId,
      });
      await _request('PUT', url);

      _lastKnownVolume = target;
      // An explicit volume change ends a mute, unless it *is* the mute write.
      if (target > 0) _volumeBeforeMute = null;
    }
  }

  Future<SpotifyHttpResponse> _request(String method, Uri url) async {
    final token = await _token();
    if (token.isEmpty) {
      throw SpotifyAuthException(
        'No Spotify access token available for volume control. Connect first, '
        'or pass the stored token to FlutterSpotifyRemote.setAccessToken().',
      );
    }

    final res = await _send(method, url, {
      'Authorization': 'Bearer $token',
      'Content-Length': '0',
    });

    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw _mapError(res);
  }

  Exception _mapError(SpotifyHttpResponse res) {
    final detail = _errorMessage(res.body);
    switch (res.statusCode) {
      case 401:
        return SpotifyAuthException(
          'Spotify access token expired or missing the '
          'user-modify-playback-state scope. Call renewSession(). ($detail)',
        );
      case 403:
        return SpotifyPremiumRequiredException(
          'Spotify rejected the volume change: $detail '
          'Volume control requires Spotify Premium.',
        );
      case 404:
        return SpotifyNoActiveDeviceException(
          'No active Spotify device to set the volume on. Start playback '
          'first, or pass an explicit deviceId. ($detail)',
        );
      default:
        return SpotifyWebApiException(res.statusCode, detail);
    }
  }

  /// Pulls `error.message` out of a Spotify error body, falling back to the raw body.
  String _errorMessage(String body) {
    if (body.isEmpty) return 'No details returned.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message'] as String? ?? body;
      }
    } on FormatException {
      // Not JSON — fall through to the raw body.
    }
    return body;
  }

  static Future<SpotifyHttpResponse> _defaultSend(
    String method,
    Uri url,
    Map<String, String> headers,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, url);
      headers.forEach(req.headers.set);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return SpotifyHttpResponse(res.statusCode, body);
    } finally {
      client.close();
    }
  }
}
