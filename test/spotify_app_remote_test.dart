import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_app_remote/spotify_app_remote.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpotifyAppRemote', () {
    final List<MethodCall> log = [];

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.spotifyappremote/method'),
        (call) async {
          log.add(call);
          return null;
        },
      );
    });

    tearDown(() => log.clear());

    test('play sends correct method and URI', () async {
      await SpotifyAppRemote.instance.play('spotify:track:123');
      expect(log.last.method, 'play');
      expect(log.last.arguments['spotifyUri'], 'spotify:track:123');
    });

    test('pause sends correct method', () async {
      await SpotifyAppRemote.instance.pause();
      expect(log.last.method, 'pause');
    });

    test('resume sends correct method', () async {
      await SpotifyAppRemote.instance.resume();
      expect(log.last.method, 'resume');
    });

    test('skipNext sends correct method', () async {
      await SpotifyAppRemote.instance.skipNext();
      expect(log.last.method, 'skipNext');
    });

    test('skipPrevious sends correct method', () async {
      await SpotifyAppRemote.instance.skipPrevious();
      expect(log.last.method, 'skipPrevious');
    });

    test('seekTo sends correct position', () async {
      await SpotifyAppRemote.instance.seekTo(30000);
      expect(log.last.method, 'seekTo');
      expect(log.last.arguments['positionMs'], 30000);
    });

    test('setShuffle sends enabled flag', () async {
      await SpotifyAppRemote.instance.setShuffle(true);
      expect(log.last.method, 'setShuffle');
      expect(log.last.arguments['shuffle'], true);
    });

    test('setRepeatMode sends mode index', () async {
      await SpotifyAppRemote.instance.setRepeatMode(2);
      expect(log.last.method, 'setRepeatMode');
      expect(log.last.arguments['repeatMode'], 2);
    });

    test('connectWithToken sends all required arguments', () async {
      await SpotifyAppRemote.instance.connectWithToken(
        clientId: 'client_id',
        redirectUrl: 'myapp://callback',
        accessToken: 'token_abc',
      );
      expect(log.last.method, 'connectWithToken');
      expect(log.last.arguments['clientId'], 'client_id');
      expect(log.last.arguments['redirectUrl'], 'myapp://callback');
      expect(log.last.arguments['accessToken'], 'token_abc');
    });

    test('disconnect sends correct method', () async {
      await SpotifyAppRemote.instance.disconnect();
      expect(log.last.method, 'disconnect');
    });
  });

  group('SpotifyTrack.fromMap', () {
    test('parses all fields correctly', () {
      final track = SpotifyTrack.fromMap({
        'trackUri':        'spotify:track:abc',
        'trackName':       'Test Track',
        'artistName':      'Test Artist',
        'albumName':       'Test Album',
        'imageIdentifier': 'img-id',
        'duration':        240000,
      });
      expect(track.uri,             'spotify:track:abc');
      expect(track.name,            'Test Track');
      expect(track.artistName,      'Test Artist');
      expect(track.albumName,       'Test Album');
      expect(track.imageIdentifier, 'img-id');
      expect(track.durationMs,      240000);
    });

    test('uses defaults for missing fields', () {
      final track = SpotifyTrack.fromMap({});
      expect(track.uri,      '');
      expect(track.durationMs, 0);
    });
  });

  group('SpotifyPlayerState.fromMap', () {
    test('parses repeat mode enum correctly', () {
      final state = SpotifyPlayerState.fromMap({
        'repeatMode': 2,
        'isPaused':   false,
      });
      expect(state.repeatMode, SpotifyRepeatMode.context);
      expect(state.isPaused,   false);
    });

    test('clamps out-of-range repeat mode', () {
      final state = SpotifyPlayerState.fromMap({'repeatMode': 99});
      expect(state.repeatMode, SpotifyRepeatMode.context);
    });
  });
}
