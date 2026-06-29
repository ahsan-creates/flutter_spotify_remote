import Flutter
import UIKit
import SpotifyiOS

// ── DEBUG: intercepts every request to nobese.com and logs it ────────────────
class SpotifyRequestLogger: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host.contains("nobese.com")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        print("[SpotifyHTTP] ► \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody, let str = String(data: body, encoding: .utf8) {
            print("[SpotifyHTTP]   Body: \(str)")
        } else {
            print("[SpotifyHTTP]   Body: (empty or binary)")
        }
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let r = response { self.client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed) }
            if let d = data {
                self.client?.urlProtocol(self, didLoad: d)
                print("[SpotifyHTTP] ◄ \(String(data: d, encoding: .utf8) ?? "<binary>")")
            }
            if let e = error {
                self.client?.urlProtocol(self, didFailWithError: e)
                print("[SpotifyHTTP] ✗ error: \(e)")
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }
    override func stopLoading() {}
}
// ─────────────────────────────────────────────────────────────────────────────

public class SpotifyAppRemotePlugin: NSObject, FlutterPlugin {

    // ── Channel names ─────────────────────────────────────────────────────
    private static let methodChannelName = "com.spotifyappremote/method"
    private static let eventChannelName  = "com.spotifyappremote/events"

    // ── Flutter ───────────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── Spotify ───────────────────────────────────────────────────────────
    private var appRemote:      SPTAppRemote?
    private var sessionManager: SPTSessionManager?
    private var pendingResult:  FlutterResult?
    private var clientId    = ""
    private var redirectUri = ""

    // Backend URLs for SPTSessionManager token swap + silent refresh.
    private var tokenSwapURL    = ""
    private var tokenRefreshURL = ""
    // Scopes saved from the last initializeSession call so renewSession can reuse them.
    private var storedScopes: [String] = []

    // Persisted so the lifecycle reconnect path and didRenew can use a fresh token.
    private var storedToken: String?

    // True once App Remote has connected successfully at least once this session.
    // Guards applicationDidBecomeActive from connecting on cold start without user intent.
    private var wasEverConnected = false

    // Prevents applicationDidBecomeActive from firing multiple concurrent reconnects.
    private var lifecycleReconnectInProgress = false

    // True when the current initializeSession was called with clientOnly: true
    // (i.e. a silent renewal, not a full OAuth flow). Used to:
    //   1. Emit the correct "source" field in SpotifyAccessTokenEvent
    //   2. Detect an expired Keychain session in didInitiate and call SDK renewSession()
    private var isSilentRenew = false

    // ── Registration ──────────────────────────────────────────────────────
    public static func register(with registrar: FlutterPluginRegistrar) {
        URLProtocol.registerClass(SpotifyRequestLogger.self)
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

        case "initializeSession":
            clientId        = args["clientId"]        as? String ?? ""
            redirectUri     = args["redirectUrl"]     as? String ?? ""
            tokenSwapURL    = args["tokenSwapURL"]    as? String ?? ""
            tokenRefreshURL = args["tokenRefreshURL"] as? String ?? ""
            let scopes      = args["scopes"]          as? [String] ?? []
            storedScopes    = scopes
            let spotifyUri  = args["spotifyUri"]      as? String ?? ""
            let clientOnly  = args["clientOnly"]      as? Bool   ?? false
            // Must be set BEFORE initializeSession() so didInitiate/didRenew
            // callbacks see the correct value.
            isSilentRenew   = clientOnly
            pendingResult   = result
            initializeSession(scopes: scopes, spotifyUri: spotifyUri, clientOnly: clientOnly)

        case "renewSession":
            // Called from Dart's _spotify.renewSession() — always a silent renewal.
            isSilentRenew = true
            pendingResult = result
            initializeSession(scopes: storedScopes, spotifyUri: "", clientOnly: true)

        case "connectAndAuthorize":
            if appRemote?.isConnected == true {
                result(nil)
                return
            }
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
            pendingResult?(FlutterError(
                code: "DISCONNECTED",
                message: "Disconnect requested",
                details: nil
            ))
            pendingResult = nil
            appRemote?.disconnect()
            result(nil)

        case "isConnected":
            result(appRemote?.isConnected ?? false)

        case "play":
            let uri = args["spotifyUri"] as? String ?? ""
            guard let api = requirePlayerAPI(result) else { return }
            api.play(uri) { [weak self] _, error in self?.settle(result, error: error) }

        case "pause":
            guard let api = requirePlayerAPI(result) else { return }
            api.pause { [weak self] _, error in self?.settle(result, error: error) }

        case "resume":
            guard let api = requirePlayerAPI(result) else { return }
            api.resume { [weak self] _, error in self?.settle(result, error: error) }

        case "skipNext":
            guard let api = requirePlayerAPI(result) else { return }
            api.skip(toNext:) { [weak self] _, error in self?.settle(result, error: error) }

        case "skipPrevious":
            guard let api = requirePlayerAPI(result) else { return }
            api.skip(toPrevious:) { [weak self] _, error in self?.settle(result, error: error) }

        case "seekTo":
            let ms = args["positionMs"] as? Int ?? 0
            guard let api = requirePlayerAPI(result) else { return }
            api.seek(toPosition: ms) { [weak self] _, error in self?.settle(result, error: error) }

        case "setShuffle":
            let on = args["shuffle"] as? Bool ?? false
            guard let api = requirePlayerAPI(result) else { return }
            api.setShuffle(on) { [weak self] _, error in self?.settle(result, error: error) }

        case "setRepeatMode":
            let raw  = args["repeatMode"] as? UInt ?? 0
            let mode = SPTAppRemotePlaybackOptionsRepeatMode(rawValue: raw) ?? .off
            guard let api = requirePlayerAPI(result) else { return }
            api.setRepeatMode(mode) { [weak self] _, error in self?.settle(result, error: error) }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Connect with stored token ─────────────────────────────────────────
    private func connectWithToken(token: String, spotifyUri: String) {
        storedToken = token

        if appRemote?.isConnected == true {
            print("[SpotifyPlugin] connectWithToken — already connected, resolving")
            pendingResult?(true)
            pendingResult = nil
            return
        }

        if appRemote == nil {
            buildAppRemote()
        }
        appRemote?.connectionParameters.accessToken = token
        if spotifyUri.isEmpty {
            print("[SpotifyPlugin] connectWithToken — connect() (no URI)")
            appRemote?.connect()
        } else {
            print("[SpotifyPlugin] connectWithToken — authorizeAndPlayURI(\(spotifyUri))")
            appRemote?.authorizeAndPlayURI(spotifyUri)
        }
    }

    // ── First-time auth via SPTSessionManager (full scopes, no tokenSwapURL) ─
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
        isSilentRenew = false
        sessionManager = SPTSessionManager(configuration: config, delegate: self)

        let scopes: SPTScope = [
            .appRemoteControl,
            .userLibraryRead,
            .userReadPlaybackState,
            .userModifyPlaybackState,
            .userReadPrivate,
            .streaming,
        ]
        sessionManager?.initiateSession(with: scopes, options: .clientOnly, campaign: nil)
    }

    // ── Session init with backend token swap + silent refresh ─────────────
    private func initializeSession(scopes: [String], spotifyUri: String, clientOnly: Bool = false) {
        guard let redirectURL = URL(string: redirectUri) else {
            pendingResult?(FlutterError(
                code: "INVALID_REDIRECT_URL",
                message: "Invalid redirect URL: \(redirectUri)",
                details: nil
            ))
            pendingResult = nil
            return
        }

        print("[SpotifyPlugin] ── initializeSession ──────────────────────────────")
        print("[SpotifyPlugin] clientId:        \(clientId)")
        print("[SpotifyPlugin] redirectUri:     \(redirectUri)")
        print("[SpotifyPlugin] tokenSwapURL:    \(tokenSwapURL)")
        print("[SpotifyPlugin] tokenRefreshURL: \(tokenRefreshURL)")
        print("[SpotifyPlugin] spotifyUri:      \(spotifyUri)")
        print("[SpotifyPlugin] clientOnly:      \(clientOnly)")
        print("[SpotifyPlugin] isSilentRenew:   \(isSilentRenew)")
        print("[SpotifyPlugin] scopes:          \(scopes)")
        print("[SpotifyPlugin] ────────────────────────────────────────────────────")

        if clientOnly {
            // ── Same-session renewal ──────────────────────────────────────
            // The existing sessionManager's session is set by didInitiate after first
            // OAuth. Creating a NEW SPTSessionManager loses that reference — the new
            // instance's session property starts as nil even though the Keychain holds
            // the data. So we reuse the existing instance and call renewSession() on it.
            if let sm = sessionManager, let session = sm.session {
                print("[SpotifyPlugin] clientOnly — reusing existing SM (isExpired=\(session.isExpired) refreshToken=\(session.refreshToken.prefix(10))...) — calling SDK renewSession()")
                sm.renewSession()
                return
            }

            // ── Cold-start renewal (app killed and relaunched) ────────────
            // No live session manager. Create a new one with tokenRefreshURL and call
            // initiateSession(clientOnly). The SDK reads Keychain:
            //   • Valid session found → didInitiate fires WITHOUT opening Spotify ✅
            //   • Expired session found → didInitiate fires (isExpired=true) → we call
            //     renewSession() from there → didRenew fires ✅
            //   • No Keychain session → didFailWith fires → Dart sees AUTH_ERROR ✅
            // Critically, NO app switch happens if a Keychain session exists.
            let config = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
            if !tokenRefreshURL.isEmpty, let url = URL(string: tokenRefreshURL) {
                config.tokenRefreshURL = url
            }
            config.playURI = spotifyUri
            sessionManager = SPTSessionManager(configuration: config, delegate: self)
            print("[SpotifyPlugin] clientOnly — cold start, calling initiateSession(clientOnly)")
            sessionManager?.initiateSession(with: buildScopes(scopes), options: .clientOnly, campaign: nil)
            return
        }

        // ── Full OAuth ────────────────────────────────────────────────────
        let config = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        if !tokenSwapURL.isEmpty, let url = URL(string: tokenSwapURL) {
            config.tokenSwapURL = url
        }
        if !tokenRefreshURL.isEmpty, let url = URL(string: tokenRefreshURL) {
            config.tokenRefreshURL = url
        }
        config.playURI = spotifyUri
        sessionManager = SPTSessionManager(configuration: config, delegate: self)
        print("[SpotifyPlugin] initiateSession options: default (full OAuth)")
        sessionManager?.initiateSession(with: buildScopes(scopes), options: .default, campaign: nil)
    }

    private func buildScopes(_ scopes: [String]) -> SPTScope {
        var result: SPTScope = []
        for scope in scopes {
            switch scope {
            case "app-remote-control":          result.insert(.appRemoteControl)
            case "user-modify-playback-state":  result.insert(.userModifyPlaybackState)
            case "user-read-playback-state":    result.insert(.userReadPlaybackState)
            case "user-read-currently-playing": result.insert(.userReadCurrentlyPlaying)
            case "user-library-read":           result.insert(.userLibraryRead)
            case "user-library-modify":         result.insert(.userLibraryModify)
            case "user-read-private":           result.insert(.userReadPrivate)
            case "user-read-email":             result.insert(.userReadEmail)
            case "playlist-read-private":       result.insert(.playlistReadPrivate)
            case "playlist-read-collaborative": result.insert(.playlistReadCollaborative)
            case "streaming":                   result.insert(.streaming)
            default: break
            }
        }
        return result
    }

    // ── Build SPTAppRemote ────────────────────────────────────────────────
    private func buildAppRemote() {
        guard let redirectURL = URL(string: redirectUri) else { return }
        let config = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        appRemote           = SPTAppRemote(configuration: config, logLevel: .error)
        appRemote?.delegate = self
    }

    // ── Handle redirect URL after Spotify app-switch ──────────────────────
    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        print("[SpotifyPlugin] application:openURL: \(url.absoluteString)")

        // SPTSessionManager handles the OAuth callback (initializeSession path).
        if sessionManager?.application(app, open: url, options: options) == true {
            print("[SpotifyPlugin] URL handled by sessionManager")
            return true
        }

        // SPTAppRemote handles the direct token URL (authorizeAndPlayURI path).
        guard let params = appRemote?.authorizationParameters(from: url) else {
            print("[SpotifyPlugin] URL not recognized by sessionManager or appRemote")
            return false
        }
        if let token = params[SPTAppRemoteAccessTokenKey] as? String {
            print("[SpotifyPlugin] authorizationParameters — got direct token")
            appRemote?.connectionParameters.accessToken = token
            storedToken = token
            appRemote?.connect()
            emit([
                "event":       "accessToken",
                "accessToken": token,
                "expiresIn":   3600,
                "source":      "directAuth",
            ])
            return true
        }
        if let errorDesc = params[SPTAppRemoteErrorDescriptionKey] as? String {
            print("[SpotifyPlugin] authorizationParameters — error: \(errorDesc)")
            pendingResult?(FlutterError(
                code: "AUTH_ERROR",
                message: errorDesc,
                details: nil
            ))
            pendingResult = nil
        }
        return false
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────
    public func applicationDidBecomeActive(_ application: UIApplication) {
        // appRemote is nil after a disconnect (reset in didDisconnectWithError).
        // Rebuild it here so we can attempt a silent reconnect on foreground.
        guard wasEverConnected,
              !lifecycleReconnectInProgress,
              appRemote?.isConnected != true,
              let token = storedToken,
              pendingResult == nil else { return }
        lifecycleReconnectInProgress = true
        if appRemote == nil { buildAppRemote() }
        print("[SpotifyPlugin] applicationDidBecomeActive — silent reconnect")
        appRemote?.connectionParameters.accessToken = token
        appRemote?.connect()
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    private func requirePlayerAPI(_ result: FlutterResult) -> SPTAppRemotePlayerAPI? {
        guard let api = appRemote?.playerAPI, appRemote?.isConnected == true else {
            result(FlutterError(
                code: "NOT_CONNECTED",
                message: "Spotify App Remote is not connected",
                details: nil
            ))
            return nil
        }
        return api
    }

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

        print("[SpotifyPlugin] didInitiate — isSilentRenew=\(isSilentRenew) isExpired=\(session.isExpired) expiresIn=\(expiresIn)s token=\(token.prefix(15))...")

        // Cold-start path: initiateSession(clientOnly) returned an expired Keychain
        // session. Call SDK renewSession() to hit tokenRefreshURL silently.
        // pendingResult stays pending until didRenew (or didFailWith) fires.
        if isSilentRenew && session.isExpired {
            print("[SpotifyPlugin] didInitiate — expired Keychain session, calling SDK renewSession()")
            sessionManager?.renewSession()
            return
        }

        let source = isSilentRenew ? "silentRefresh" : "firstAuth"
        storedToken   = token
        isSilentRenew = false

        print("[SpotifyPlugin] didInitiate — resolving pendingResult (source=\(source))")
        pendingResult?(nil)
        pendingResult = nil

        emit([
            "event":       "accessToken",
            "accessToken": token,
            "expiresIn":   expiresIn,
            "source":      source,
        ])
    }

    public func sessionManager(
        manager: SPTSessionManager,
        didFailWith error: Error
    ) {
        let msg = error.localizedDescription
        print("[SpotifyPlugin] didFailWith — error: \(error)")
        print("[SpotifyPlugin] didFailWith — localizedDescription: \(msg)")
        isSilentRenew = false
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
        storedToken   = token
        isSilentRenew = false

        print("[SpotifyPlugin] didRenew — token=\(token.prefix(15))... expiresIn=\(expiresIn)s")

        // CRITICAL: resolve the pending initializeSession/renewSession Flutter future.
        // Without this, the Dart await never returns, _connectingInProgress stays true
        // forever, and all subsequent connectAndAuthorize/renewSession calls are blocked.
        pendingResult?(nil)
        pendingResult = nil

        // Update the stored token so the next connect() call uses the fresh one.
        // Do NOT call appRemote?.connect() here — Dart receives the SpotifyAccessTokenEvent
        // and calls connectWithToken, which calls connect(). A second connect() call from
        // here races with that and causes both attempts to fail with "Connection attempt failed."
        appRemote?.connectionParameters.accessToken = token

        emit([
            "event":       "accessToken",
            "accessToken": token,
            "expiresIn":   expiresIn,
            "source":      "silentRefresh",
        ])
    }
}

// ── SPTAppRemoteDelegate ──────────────────────────────────────────────────
extension SpotifyAppRemotePlugin: SPTAppRemoteDelegate {

    public func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        wasEverConnected = true
        lifecycleReconnectInProgress = false
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { _, _ in })
        print("[SpotifyPlugin] appRemoteDidEstablishConnection")
        pendingResult?(true)
        pendingResult = nil
        emit(["event": "connected"])
    }

    public func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        let msg = error?.localizedDescription ?? "Connection failed"
        print("[SpotifyPlugin] didFailConnectionAttemptWithError: \(msg)")
        lifecycleReconnectInProgress = false
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
        let msg = error?.localizedDescription ?? "Disconnected"
        print("[SpotifyPlugin] didDisconnectWithError: \(msg)")
        // Nil out the appRemote instance. The SDK returns "Connection attempt failed"
        // when connect() is called on the same instance after didDisconnectWithError.
        // connectWithToken rebuilds it fresh (via buildAppRemote) before the next connect().
        self.appRemote?.delegate = nil
        self.appRemote = nil
        emit([
            "event":   "disconnected",
            "message": msg,
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
