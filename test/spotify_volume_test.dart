import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';

void main() {
  group('SpotifyVolumeController', () {
    late List<Uri> requests;
    late SpotifyHttpResponse Function(String method, Uri url) respond;

    SpotifyVolumeController build({String token = 'token'}) =>
        SpotifyVolumeController(
          tokenProvider: () async => token,
          send: (method, url, headers) async {
            requests.add(url);
            return respond(method, url);
          },
        );

    SpotifyHttpResponse playerBody(int volume) => SpotifyHttpResponse(
          200,
          jsonEncode({
            'device': {'volume_percent': volume}
          }),
        );

    setUp(() {
      requests = [];
      respond = (method, url) =>
          method == 'GET' ? playerBody(50) : const SpotifyHttpResponse(204, '');
    });

    test('setVolume PUTs the clamped percent', () async {
      final volume = build();

      await volume.setVolume(140);

      expect(requests.single.path, '/v1/me/player/volume');
      expect(requests.single.queryParameters['volume_percent'], '100');
      expect(volume.lastKnownVolume, 100);
    });

    test('setVolume forwards an explicit deviceId', () async {
      await build().setVolume(30, deviceId: 'abc');
      expect(requests.single.queryParameters['device_id'], 'abc');
    });

    test('getVolume reads volume_percent from the active device', () async {
      expect(await build().getVolume(), 50);
    });

    test('getVolume throws when no device is active', () async {
      respond = (_, __) => const SpotifyHttpResponse(204, '');
      expect(build().getVolume, throwsA(isA<SpotifyNoActiveDeviceException>()));
    });

    test('volumeUp steps up from the current volume', () async {
      final volume = build();

      await volume.volumeUp(step: 15);

      expect(requests.last.queryParameters['volume_percent'], '65');
    });

    test('volumeDown clamps at zero', () async {
      final volume = build();
      await volume.setVolume(5);

      await volume.volumeDown();

      expect(requests.last.queryParameters['volume_percent'], '0');
    });

    test('mute then unmute restores the previous volume', () async {
      final volume = build();
      await volume.setVolume(70);

      await volume.mute();
      expect(volume.isMuted, isTrue);
      expect(requests.last.queryParameters['volume_percent'], '0');

      await volume.unmute();
      expect(volume.isMuted, isFalse);
      expect(requests.last.queryParameters['volume_percent'], '70');
    });

    test('mute is idempotent and never remembers zero', () async {
      final volume = build();
      await volume.setVolume(70);

      await volume.mute();
      await volume.mute();
      await volume.unmute();

      expect(requests.last.queryParameters['volume_percent'], '70');
    });

    test('toggleMute alternates', () async {
      final volume = build();
      await volume.setVolume(40);

      await volume.toggleMute();
      expect(volume.isMuted, isTrue);
      await volume.toggleMute();
      expect(volume.isMuted, isFalse);
      expect(volume.lastKnownVolume, 40);
    });

    test('rapid setVolume calls coalesce to the latest value', () async {
      final volume = build();

      await Future.wait([
        volume.setVolume(10),
        volume.setVolume(20),
        volume.setVolume(30),
      ]);

      // First write goes out immediately, the rest collapse into one.
      expect(requests.length, lessThan(3));
      expect(requests.last.queryParameters['volume_percent'], '30');
      expect(volume.lastKnownVolume, 30);
    });

    test('403 reports that Premium is required', () async {
      respond = (_, __) => SpotifyHttpResponse(
            403,
            jsonEncode({
              'error': {'status': 403, 'message': 'Player command failed'}
            }),
          );

      expect(
        () => build().setVolume(50),
        throwsA(isA<SpotifyPremiumRequiredException>()),
      );
    });

    test('404 reports no active device', () async {
      respond = (_, __) => const SpotifyHttpResponse(404, '');
      expect(
        () => build().setVolume(50),
        throwsA(isA<SpotifyNoActiveDeviceException>()),
      );
    });

    test('401 surfaces as an auth error', () async {
      respond = (_, __) => const SpotifyHttpResponse(401, '');
      expect(
        () => build().setVolume(50),
        throwsA(isA<SpotifyAuthException>()),
      );
    });

    test('other failures surface the API message', () async {
      respond = (_, __) => SpotifyHttpResponse(
            500,
            jsonEncode({
              'error': {'message': 'Server error'}
            }),
          );

      expect(
        () => build().setVolume(50),
        throwsA(isA<SpotifyWebApiException>().having(
          (e) => e.message,
          'message',
          'Server error',
        )),
      );
    });

    test('an empty token fails before any request', () async {
      expect(
        () => build(token: '').setVolume(50),
        throwsA(isA<SpotifyAuthException>()),
      );
      expect(requests, isEmpty);
    });
  });
}
