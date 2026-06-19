import 'dart:async';
import 'package:flutter/services.dart';
import 'spotify_app_remote_platform.dart';
import 'models/spotify_event.dart';
import 'models/spotify_player_state.dart';
import 'models/spotify_connection_status.dart';
import 'exceptions/spotify_exceptions.dart';

/// Default [SpotifyAppRemotePlatform] implementation using Flutter method/event channels.
class MethodChannelSpotifyAppRemote extends SpotifyAppRemotePlatform {
  static const _method = MethodChannel('com.spotifyappremote/method');
  static const _event = EventChannel('com.spotifyappremote/events');

  late final Stream<SpotifyEvent> _eventStream = _event
      .receiveBroadcastStream()
      .map(_parseEvent)
      .asBroadcastStream();

  @override
  Stream<SpotifyEvent> get onEvent => _eventStream;

  // ── Parse raw event map from native ───────────────────────────────────

  SpotifyEvent _parseEvent(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final event = map['event'] as String? ?? '';

    switch (event) {
      case 'playerState':
        return SpotifyPlayerStateChangedEvent(
          SpotifyPlayerState.fromMap(map),
        );
      case 'connected':
        return const SpotifyConnectionChangedEvent(
          SpotifyConnectionStatus.connected,
        );
      case 'disconnected':
        return SpotifyConnectionChangedEvent(
          SpotifyConnectionStatus.disconnected,
          message: map['message'] as String?,
        );
      case 'connectionFailed':
        final code = map['code'] as String? ?? '';
        final status = switch (code) {
          'TOKEN_EXPIRED' => SpotifyConnectionStatus.tokenExpired,
          'SPOTIFY_NOT_INSTALLED' => SpotifyConnectionStatus.notInstalled,
          _ => SpotifyConnectionStatus.failed,
        };
        return SpotifyConnectionChangedEvent(
          status,
          message: map['message'] as String?,
        );
      case 'accessToken':
        return SpotifyAccessTokenEvent(
          map['accessToken'] as String? ?? '',
          map['expiresIn'] as int? ?? 3600,
        );
      default:
        return const SpotifyConnectionChangedEvent(
          SpotifyConnectionStatus.disconnected,
        );
    }
  }

  // ── Auth & Connection ──────────────────────────────────────────────────

  @override
  Future<void> connectWithToken({
    required String clientId,
    required String redirectUrl,
    required String accessToken,
    String spotifyUri = '',
  }) async {
    try {
      await _method.invokeMethod<void>('connectWithToken', {
        'clientId': clientId,
        'redirectUrl': redirectUrl,
        'accessToken': accessToken,
        'spotifyUri': spotifyUri,
      });
    } on PlatformException catch (e) {
      _throwNative(e);
    }
  }

  @override
  Future<void> connectAndAuthorize({
    required String clientId,
    required String redirectUrl,
    String spotifyUri = '',
  }) async {
    try {
      await _method.invokeMethod<void>('connectAndAuthorize', {
        'clientId': clientId,
        'redirectUrl': redirectUrl,
        'spotifyUri': spotifyUri,
      });
    } on PlatformException catch (e) {
      _throwNative(e);
    }
  }

  @override
  Future<void> disconnect() async =>
      _method.invokeMethod<void>('disconnect');

  @override
  Future<bool> isConnected() async =>
      await _method.invokeMethod<bool>('isConnected') ?? false;

  @override
  Future<String> getAccessToken() async {
    try {
      return await _method.invokeMethod<String>('getAccessToken') ?? '';
    } on PlatformException catch (e) {
      _throwNative(e);
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────

  @override
  Future<void> play(String uri) =>
      _invokePlayback('play', {'spotifyUri': uri});

  @override
  Future<void> pause() => _invokePlayback('pause');

  @override
  Future<void> resume() => _invokePlayback('resume');

  @override
  Future<void> skipNext() => _invokePlayback('skipNext');

  @override
  Future<void> skipPrevious() => _invokePlayback('skipPrevious');

  @override
  Future<void> seekTo(int positionMs) =>
      _invokePlayback('seekTo', {'positionMs': positionMs});

  @override
  Future<void> setShuffle(bool enabled) =>
      _invokePlayback('setShuffle', {'shuffle': enabled});

  @override
  Future<void> setRepeatMode(int mode) =>
      _invokePlayback('setRepeatMode', {'repeatMode': mode});

  Future<void> _invokePlayback(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      await _method.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw SpotifyCommandException(method, e.message ?? 'Unknown error');
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────

  Never _throwNative(PlatformException e) {
    switch (e.code) {
      case 'SPOTIFY_NOT_INSTALLED':
        throw SpotifyNotInstalledException();
      case 'TOKEN_EXPIRED':
      case 'AUTH_ERROR':
        throw SpotifyAuthException(e.message ?? 'Auth failed');
      default:
        throw SpotifyConnectionException(e.code, e.message ?? 'Unknown');
    }
  }
}
