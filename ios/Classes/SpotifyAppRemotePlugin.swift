import Flutter
import UIKit
import SpotifyiOS

public class SpotifyAppRemotePlugin: NSObject, FlutterPlugin {

    // ── Channel names ─────────────────────────────────────────────────────
    private static let methodChannelName = "com.spotifyappremote/method"
    private static let eventChannelName  = "com.spotifyappremote/events"

    // ── Flutter ───────────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── Spotify ───────────────────────────────────────────────────────────
    private var appRemote:      SPTAppRemote?
    private var sessionManager: SPTSessionManager?   // used by connectAndAuthorize
    private var pendingResult:  FlutterResult?
    private var clientId    = ""
    private var redirectUri = ""

    // ── Registration ──────────────────────────────────────────────────────
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )

        let instance = SpotifyAppRemotePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)
        eventChannel.setStreamHandler(instance)
    }

    // ── Method handler ────────────────────────────────────────────────────
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {

        case "connectWithToken":
            clientId    = args["clientId"]    as? String ?? clientId
            redirectUri = args["redirectUrl"] as? String ?? redirectUri
            let token      = args["accessToken"] as? String ?? ""
            let spotifyUri = args["spotifyUri"]  as? String ?? ""
            pendingResult  = result
            connectWithToken(token: token, spotifyUri: spotifyUri)

        case "connectAndAuthorize":
            clientId    = args["clientId"]    as? String ?? ""
            redirectUri = args["redirectUrl"] as? String ?? ""
            pendingResult  = result
            authorizeWithSessionManager()

        case "getAccessToken":
            if let token = appRemote?.connectionParameters.accessToken,
               appRemote?.isConnected == true {
                result(token)
            } else {
                result(FlutterError(
                    code: "NOT_CONNECTED",
                    message: "Not connected to Spotify",
                    details: nil
                ))
            }

        case "disconnect":
            appRemote?.disconnect()
            appRemote = nil
            result(nil)

        case "isConnected":
            result(appRemote?.isConnected ?? false)

        case "play":
            let uri = args["spotifyUri"] as? String ?? ""
            appRemote?.playerAPI?.play(uri) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "pause":
            appRemote?.playerAPI?.pause { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "resume":
            appRemote?.playerAPI?.resume { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "skipNext":
            appRemote?.playerAPI?.skip(toNext:) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "skipPrevious":
            appRemote?.playerAPI?.skip(toPrevious:) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "seekTo":
            let ms = args["positionMs"] as? Int ?? 0
            appRemote?.playerAPI?.seek(toPosition: ms) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "setShuffle":
            let on = args["shuffle"] as? Bool ?? false
            appRemote?.playerAPI?.setShuffle(on) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        case "setRepeatMode":
            let raw  = args["repeatMode"] as? UInt ?? 0
            let mode = SPTAppRemotePlaybackOptionsRepeatMode(rawValue: raw) ?? .off
            appRemote?.playerAPI?.setRepeatMode(mode) { [weak self] _, error in
                self?.settle(result, error: error)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Connect with stored token (silent, unchanged) ─────────────────────
    private func connectWithToken(token: String, spotifyUri: String) {
        buildAppRemote()
        appRemote?.connectionParameters.accessToken = token
        appRemote?.connect()
    }

    // ── First-time auth via SPTSessionManager (full scopes) ───────────────
    //
    // SPTAppRemote.authorizeAndPlayURI only requests app-remote-control scope,
    // causing 403s for any Web API calls (saved tracks, playback state, etc.).
    // SPTSessionManager.initiateSession lets us request all required scopes.
    private func authorizeWithSessionManager() {
        guard let redirectURL = URL(string: redirectUri) else {
            pendingResult?(FlutterError(
                code: "INVALID_REDIRECT_URL",
                message: "Invalid redirect URL: \(redirectUri)",
                details: nil
            ))
            pendingResult = nil
            return
        }

        let config = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        sessionManager = SPTSessionManager(configuration: config, delegate: self)

        let scopes: SPTScope = [
            .appRemoteControl,
            .userLibraryRead,
            .userReadPlaybackState,
            .userModifyPlaybackState,
            .userReadPrivate,
            .streaming,
        ]
        sessionManager?.initiateSession(with: scopes, options: .default, campaign: nil)
    }

    // ── Build SPTAppRemote ────────────────────────────────────────────────
    private func buildAppRemote() {
        guard let redirectURL = URL(string: redirectUri) else { return }
        let config = SPTConfiguration(
            clientID: clientId,
            redirectURL: redirectURL
        )
        appRemote           = SPTAppRemote(configuration: config, logLevel: .error)
        appRemote?.delegate = self
    }

    // ── Handle redirect URL after Spotify app-switch ──────────────────────
    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // SPTSessionManager handles the OAuth callback for connectAndAuthorize.
        // Must be tried first so it can capture the full-scope token.
        if sessionManager?.application(app, open: url, options: options) == true {
            return true
        }

        // SPTAppRemote handles the token URL for the connectWithToken silent path.
        guard let params = appRemote?.authorizationParameters(from: url) else {
            return false
        }
        if let token = params[SPTAppRemoteAccessTokenKey] as? String {
            appRemote?.connectionParameters.accessToken = token
            appRemote?.connect()
            emit([
                "event":       "accessToken",
                "accessToken": token,
                "expiresIn":   3600,
            ])
            return true
        }
        if let errorDesc = params[SPTAppRemoteErrorDescriptionKey] as? String {
            pendingResult?(FlutterError(
                code: "AUTH_ERROR",
                message: errorDesc,
                details: nil
            ))
            pendingResult = nil
        }
        return false
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    private func settle(_ result: FlutterResult, error: Error?) {
        if let error = error {
            result(FlutterError(
                code: "SPOTIFY_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        } else {
            result(nil)
        }
    }

    private func emit(_ data: [String: Any]) {
        DispatchQueue.main.async { self.eventSink?(data) }
    }
}

// ── SPTSessionManagerDelegate ─────────────────────────────────────────────
extension SpotifyAppRemotePlugin: SPTSessionManagerDelegate {

    public func sessionManager(
        manager: SPTSessionManager,
        didInitiate session: SPTSession
    ) {
        let token     = session.accessToken
        let expiresIn = max(Int(session.expirationDate.timeIntervalSinceNow), 0)

        // Resolve the pending connectAndAuthorize call immediately — Flutter
        // side is fire-and-forget so this just unblocks the method channel.
        pendingResult?(nil)
        pendingResult = nil

        // Emit token to Flutter; Flutter will call connectWithToken via the
        // method channel once the event loop runs (app already fully active).
        // WHY: calling appRemote?.connect() here (inside the URL open handler,
        // before applicationDidBecomeActive) fails silently — SPTAppRemote
        // cannot establish a connection until the app is in the foreground.
        emit([
            "event":       "accessToken",
            "accessToken": token,
            "expiresIn":   expiresIn,
        ])
    }

    public func sessionManager(
        manager: SPTSessionManager,
        didFailWith error: Error
    ) {
        let msg = error.localizedDescription
        pendingResult?(FlutterError(code: "AUTH_ERROR", message: msg, details: nil))
        pendingResult = nil
        emit(["event": "connectionFailed", "code": "AUTH_ERROR", "message": msg])
    }

    public func sessionManager(
        manager: SPTSessionManager,
        didRenew session: SPTSession
    ) {
        let token     = session.accessToken
        let expiresIn = max(Int(session.expirationDate.timeIntervalSinceNow), 0)
        emit([
            "event":       "accessToken",
            "accessToken": token,
            "expiresIn":   expiresIn,
        ])
    }
}

// ── SPTAppRemoteDelegate ──────────────────────────────────────────────────
extension SpotifyAppRemotePlugin: SPTAppRemoteDelegate {

    public func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, _ in })
        pendingResult?(true)
        pendingResult = nil
        emit(["event": "connected"])
    }

    public func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        let msg = error?.localizedDescription ?? "Connection failed"
        let isAuthError = msg.lowercased().contains("token")
            || msg.lowercased().contains("401")
            || msg.lowercased().contains("unauthorized")
        let code = isAuthError ? "TOKEN_EXPIRED" : "CONNECTION_FAILED"
        pendingResult?(FlutterError(code: code, message: msg, details: nil))
        pendingResult = nil
        emit(["event": "connectionFailed", "code": code, "message": msg])
    }

    public func appRemote(
        _ appRemote: SPTAppRemote,
        didDisconnectWithError error: Error?
    ) {
        emit([
            "event":   "disconnected",
            "message": error?.localizedDescription ?? "Disconnected",
        ])
    }
}

// ── SPTAppRemotePlayerStateDelegate ──────────────────────────────────────
extension SpotifyAppRemotePlugin: SPTAppRemotePlayerStateDelegate {

    public func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        emit([
            "event":            "playerState",
            "isPaused":         playerState.isPaused,
            "trackUri":         playerState.track.uri,
            "trackName":        playerState.track.name,
            "artistName":       playerState.track.artist.name,
            "albumName":        playerState.track.album.name,
            "imageIdentifier":  playerState.track.imageIdentifier,
            "playbackPosition": playerState.playbackPosition,
            "duration":         playerState.track.duration,
            "isShuffling":      playerState.playbackOptions.isShuffling,
            "repeatMode":       playerState.playbackOptions.repeatMode.rawValue,
        ])
    }
}

// ── FlutterStreamHandler ──────────────────────────────────────────────────
extension SpotifyAppRemotePlugin: FlutterStreamHandler {

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
