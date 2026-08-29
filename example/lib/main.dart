import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spotify_remote/flutter_spotify_remote.dart';

// ── Replace these with your Spotify developer app credentials ─────────────
const _clientId = 'fd6a6ef108634181b17f1fc31b9d2775';
const _redirectUrl = 'spotifyappremote://callback';
// ─────────────────────────────────────────────────────────────────────────

void main() => runApp(const SpotifyExampleApp());

class SpotifyExampleApp extends StatelessWidget {
  const SpotifyExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify App Remote Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
        useMaterial3: true,
      ),
      home: const SpotifyHomePage(),
    );
  }
}

class SpotifyHomePage extends StatefulWidget {
  const SpotifyHomePage({super.key});

  @override
  State<SpotifyHomePage> createState() => _SpotifyHomePageState();
}

class _SpotifyHomePageState extends State<SpotifyHomePage> {
  final _spotify = FlutterSpotifyRemote.instance;

  StreamSubscription<SpotifyEvent>? _eventSub;
  SpotifyPlayerState? _playerState;
  SpotifyConnectionStatus _connectionStatus =
      SpotifyConnectionStatus.disconnected;
  String _statusMessage = 'Not connected';

  @override
  void initState() {
    super.initState();
    _listenToEvents();
    _tryConnectWithStoredToken();
  }

  void _listenToEvents() {
    _eventSub = _spotify.onEvent.listen((event) {
      switch (event) {
        case SpotifyPlayerStateChangedEvent(:final playerState):
          setState(() => _playerState = playerState);

        case SpotifyConnectionChangedEvent(:final status, :final message):
          setState(() {
            _connectionStatus = status;
            _statusMessage = switch (status) {
              SpotifyConnectionStatus.connected => 'Connected',
              SpotifyConnectionStatus.disconnected => 'Disconnected',
              SpotifyConnectionStatus.tokenExpired =>
                'Token expired — reconnecting…',
              SpotifyConnectionStatus.notInstalled =>
                'Spotify is not installed',
              SpotifyConnectionStatus.failed => 'Connection failed: $message',
            };
          });
          if (status == SpotifyConnectionStatus.tokenExpired) {
            _connectAndAuthorize();
          }

        case SpotifyAccessTokenEvent(:final accessToken, :final expiresIn):
          // Persist token so next launch skips the app-switch
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('spotify_token', accessToken);
            prefs.setInt(
              'spotify_token_expires',
              DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
            );
          });
      }
    });
  }

  Future<void> _tryConnectWithStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_token');
    final expiresAt = prefs.getInt('spotify_token_expires') ?? 0;

    if (token != null && DateTime.now().millisecondsSinceEpoch < expiresAt) {
      try {
        await _spotify.connectWithToken(
          clientId: _clientId,
          redirectUrl: _redirectUrl,
          accessToken: token,
        );
      } on SpotifyAuthException {
        await _connectAndAuthorize();
      } on SpotifyNotInstalledException {
        setState(() => _statusMessage = 'Spotify is not installed');
      }
    } else {
      await _connectAndAuthorize();
    }
  }

  Future<void> _connectAndAuthorize() async {
    try {
      await _spotify.connectAndAuthorize(
        clientId: _clientId,
        redirectUrl: _redirectUrl,
      );
    } on SpotifyNotInstalledException {
      setState(() => _statusMessage = 'Spotify is not installed');
    } on SpotifyConnectionException catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    }
  }

  Future<void> _disconnect() async {
    await _spotify.disconnect();
    setState(() {
      _playerState = null;
      _connectionStatus = SpotifyConnectionStatus.disconnected;
      _statusMessage = 'Disconnected';
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectionStatus == SpotifyConnectionStatus.connected;
    final track = _playerState?.track;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spotify App Remote'),
        backgroundColor: const Color(0xFF1DB954),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Status chip ──────────────────────────────────────────────
            Chip(
              avatar: Icon(
                connected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: connected ? Colors.green : Colors.grey,
              ),
              label: Text(_statusMessage),
            ),
            const SizedBox(height: 24),

            // ── Now Playing card ─────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: track == null
                    ? const Center(child: Text('No track playing'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(track.artistName),
                          Text(
                            track.albumName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: track.durationMs > 0
                                ? (_playerState!.playbackPosition /
                                    track.durationMs)
                                : 0,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_fmt(_playerState!.playbackPosition)} '
                            '/ ${_fmt(track.durationMs)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Playback controls ────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filled(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: connected ? () => _spotify.skipPrevious() : null,
                ),
                IconButton.filled(
                  iconSize: 48,
                  icon: Icon(
                    _playerState?.isPaused ?? true
                        ? Icons.play_arrow
                        : Icons.pause,
                  ),
                  onPressed: connected
                      ? () => _playerState?.isPaused ?? true
                          ? _spotify.resume()
                          : _spotify.pause()
                      : null,
                ),
                IconButton.filled(
                  icon: const Icon(Icons.skip_next),
                  onPressed: connected ? () => _spotify.skipNext() : null,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Shuffle & Repeat ─────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: (_playerState?.isShuffling ?? false)
                        ? const Color(0xFF1DB954)
                        : null,
                  ),
                  onPressed: connected
                      ? () => _spotify
                          .setShuffle(!(_playerState?.isShuffling ?? false))
                      : null,
                ),
                IconButton(
                  icon: Icon(
                    _playerState?.repeatMode == SpotifyRepeatMode.track
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color:
                        (_playerState?.repeatMode ?? SpotifyRepeatMode.off) !=
                                SpotifyRepeatMode.off
                            ? const Color(0xFF1DB954)
                            : null,
                  ),
                  onPressed: connected
                      ? () {
                          final current =
                              _playerState?.repeatMode ?? SpotifyRepeatMode.off;
                          final next = SpotifyRepeatMode.values[
                              (current.index + 1) %
                                  SpotifyRepeatMode.values.length];
                          _spotify.setRepeatMode(next.index);
                        }
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Play a specific track ────────────────────────────────────
            FilledButton.icon(
              icon: const Icon(Icons.music_note),
              label: const Text('Play "Bohemian Rhapsody"'),
              onPressed: connected
                  ? () => _spotify.play('spotify:track:7tFiyTwD0nx5a1eklYtX2J')
                  : null,
            ),

            const Spacer(),

            // ── Connect / Disconnect ──────────────────────────────────────
            OutlinedButton(
              onPressed: connected ? _disconnect : _connectAndAuthorize,
              child: Text(connected ? 'Disconnect' : 'Connect to Spotify'),
            ),
          ],
        ),
      ),
    );
  }

  /// Format milliseconds as `m:ss`.
  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final min = s ~/ 60;
    final sec = s % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}
