import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';

/// A request captured by [_FakeHttpClient].
class _Sent {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  _Sent(this.method, this.url, this.headers);
}

/// Exercises the real `dart:io` sender end to end without touching the network.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.sent, this.respond);

  final List<_Sent> sent;
  final (int, String) Function(String method, Uri url) respond;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(method, url, sent, respond);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.method, this.uri, this.sent, this.respond);

  @override
  final String method;
  @override
  final Uri uri;
  final List<_Sent> sent;
  final (int, String) Function(String method, Uri url) respond;
  final _FakeHeaders _headers = _FakeHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    sent.add(_Sent(method, uri, Map.of(_headers.values)));
    final (status, body) = respond(method, uri);
    return _FakeResponse(status, body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name] = '$value';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeResponse(this.statusCode, String body)
      : super(Stream.value(utf8.encode(body)));

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final remote = FlutterSpotifyRemote.instance;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<_Sent> sent;
  late (int, String) Function(String method, Uri url) respond;
  late String platformToken;
  MockStreamHandlerEventSink? events;

  /// Runs [body] with every `HttpClient` replaced by the fake.
  Future<T> withHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
        body,
        createHttpClient: (_) => _FakeHttpClient(sent, respond),
      );

  setUpAll(() {
    messenger.setMockStreamHandler(
      const EventChannel('com.spotifyappremote/events'),
      MockStreamHandler.inline(
        onListen: (_, sink) => events = sink,
        onCancel: (_) => events = null,
      ),
    );
  });

  setUp(() {
    sent = [];
    platformToken = '';
    respond = (method, _) => method == 'GET'
        ? (200, jsonEncode({'device': {'volume_percent': 55}}))
        : (204, '');
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.spotifyappremote/method'),
      (call) async => call.method == 'getAccessToken' ? platformToken : null,
    );
  });

  tearDown(() => remote.disconnect());

  test('connectWithToken token authorizes volume requests', () async {
    await remote.connectWithToken(
      clientId: 'id',
      redirectUrl: 'app://cb',
      accessToken: 'from-connect',
    );

    await withHttp(() => remote.setVolume(40));

    final req = sent.single;
    expect(req.method, 'PUT');
    expect(req.url.host, 'api.spotify.com');
    expect(req.url.path, '/v1/me/player/volume');
    expect(req.url.queryParameters['volume_percent'], '40');
    expect(req.headers['Authorization'], 'Bearer from-connect');
  });

  test('setAccessToken supplies the token on Android', () async {
    remote.setAccessToken('manual');

    final volume = await withHttp(remote.getVolume);

    expect(volume, 55);
    expect(sent.single.method, 'GET');
    expect(sent.single.headers['Authorization'], 'Bearer manual');
  });

  test('falls back to the platform getAccessToken', () async {
    platformToken = 'from-platform';

    await withHttp(() => remote.setVolume(10));

    expect(sent.single.headers['Authorization'], 'Bearer from-platform');
  });

  test('tokens from SpotifyAccessTokenEvent are cached', () async {
    await remote.connectAndAuthorize(clientId: 'id', redirectUrl: 'app://cb');
    await pumpEventQueue();

    events!.success({'event': 'accessToken', 'accessToken': 'from-event'});
    await pumpEventQueue();

    await withHttp(() => remote.setVolume(25));

    expect(sent.single.headers['Authorization'], 'Bearer from-event');
  });

  test('disconnect clears the cached token and volume state', () async {
    remote.setAccessToken('stale');
    await withHttp(() => remote.setVolume(80));
    expect(remote.lastKnownVolume, 80);

    await remote.disconnect();

    expect(remote.lastKnownVolume, isNull);
    await expectLater(
      withHttp(() => remote.setVolume(50)),
      throwsA(isA<SpotifyAuthException>()),
    );
    expect(sent, hasLength(1));
  });

  test('HTTP errors map to typed exceptions through the real sender', () async {
    remote.setAccessToken('token');
    respond = (_, __) => (
          403,
          jsonEncode({
            'error': {'status': 403, 'message': 'Player command failed'}
          }),
        );

    await expectLater(
      withHttp(() => remote.setVolume(50)),
      throwsA(isA<SpotifyPremiumRequiredException>()),
    );
  });
}
