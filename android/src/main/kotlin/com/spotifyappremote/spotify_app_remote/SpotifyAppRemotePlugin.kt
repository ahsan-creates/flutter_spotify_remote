package com.spotifyappremote.spotify_app_remote

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.protocol.types.PlayerState
import com.spotify.sdk.android.auth.AuthorizationClient
import com.spotify.sdk.android.auth.AuthorizationRequest
import com.spotify.sdk.android.auth.AuthorizationResponse
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/**
 * Flutter plugin wrapping the Spotify Android App Remote SDK.
 *
 * App Remote alone can control playback but never yields a Web API token, so
 * authorization goes through the Spotify auth library (`AuthorizationClient`)
 * and — when a backend token-swap endpoint is configured — exchanges the
 * returned code for an access/refresh token pair. This mirrors what
 * `SPTSessionManager` does on iOS so both platforms emit the same
 * `accessToken` events and honour the same method contract.
 */
class SpotifyAppRemotePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler,
    ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var eventSink: EventChannel.EventSink? = null
    private var spotifyAppRemote: SpotifyAppRemote? = null

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // ── Session config, set by initializeSession/connect* ──────────────────
    private var clientId = ""
    private var redirectUrl = ""
    private var tokenSwapURL = ""
    private var tokenRefreshURL = ""
    private var storedScopes: List<String> = emptyList()
    private var pendingSpotifyUri = ""
    private var browserRedirectUri = ""
    private var browserAuthAttempted = false
    private var authRetryAttempted = false
    private var wantsWebApiToken = false

    private var accessToken: String? = null
    private var refreshToken: String? = null

    /// The Dart result waiting on an in-flight auth round trip.
    private var pendingResult: Result? = null

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    companion object {
        const val METHOD_CHANNEL = "com.spotifyappremote/method"
        const val EVENT_CHANNEL = "com.spotifyappremote/events"
        private const val AUTH_REQUEST_CODE = 0x5170 // arbitrary, plugin-local
        private const val PREFS = "com.spotifyappremote.session"
        private const val KEY_REFRESH = "refreshToken"
        // The browser flow can outlive our process: Android may evict the app
        // while the browser is foreground, and the redirect then starts a fresh
        // one. Persist everything the code exchange needs.
        private const val KEY_CLIENT_ID = "pendingClientId"
        private const val KEY_SWAP_URL = "pendingTokenSwapURL"
        private const val KEY_REFRESH_URL = "pendingTokenRefreshURL"
        private const val KEY_BROWSER_REDIRECT = "pendingBrowserRedirect"

        /** Host of the browser-flow redirect URI: <scheme>://spotify-auth */
        const val BROWSER_REDIRECT_HOST = "spotify-auth"

        @Volatile
        private var liveInstance: SpotifyAppRemotePlugin? = null

        /** Called by [SpotifyBrowserAuthActivity] when the OAuth redirect lands. */
        @JvmStatic
        fun onBrowserRedirect(uri: android.net.Uri) {
            val inst = liveInstance
            android.util.Log.i("SpotifyAppRemote", "onBrowserRedirect liveInstance=${inst != null}")
            inst?.handleBrowserRedirect(uri)
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        refreshToken = prefs.getString(KEY_REFRESH, null)
        // Restore any in-flight browser authorization so a redirect that lands
        // in a fresh process can still complete its token exchange.
        clientId = prefs.getString(KEY_CLIENT_ID, "") ?: ""
        tokenSwapURL = prefs.getString(KEY_SWAP_URL, "") ?: ""
        tokenRefreshURL = prefs.getString(KEY_REFRESH_URL, "") ?: ""
        browserRedirectUri = prefs.getString(KEY_BROWSER_REDIRECT, "") ?: ""
        liveInstance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        spotifyAppRemote?.let { SpotifyAppRemote.disconnect(it) }
        spotifyAppRemote = null
        if (liveInstance === this) liveInstance = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    // ── Method channel ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {

            "initializeSession" -> {
                clientId = call.argument<String>("clientId") ?: ""
                redirectUrl = call.argument<String>("redirectUrl") ?: ""
                tokenSwapURL = call.argument<String>("tokenSwapURL") ?: ""
                tokenRefreshURL = call.argument<String>("tokenRefreshURL") ?: ""
                storedScopes = call.argument<List<String>>("scopes") ?: emptyList()
                pendingSpotifyUri = call.argument<String>("spotifyUri") ?: ""
                val clientOnly = call.argument<Boolean>("clientOnly") ?: false
                if (clientOnly) {
                    silentRenew(result)
                } else {
                    // Android differs from iOS here. iOS must run SPTSessionManager
                    // first, but App Remote on Android authorizes itself through the
                    // Spotify app's own auth view — a different channel from
                    // AuthorizationClient's app-to-app SSO, which some app/account
                    // combinations reject outright. Connect first so playback works,
                    // then fetch a Web API token separately and non-fatally.
                    browserAuthAttempted = false
                    authRetryAttempted = false
                    wantsWebApiToken = true
                    if (accessToken.isNullOrEmpty()) {
                        // No grant yet. App Remote's own auth view cannot be
                        // used to create one: Spotify is a background app, and
                        // Android 14+ blocks background activity launches
                        // ("Background activity launch blocked!"), so
                        // showAuthView(true) silently never appears. Authorize
                        // from OUR foreground activity first, then connect with
                        // the resulting token.
                        beginAuthorization(result)
                    } else {
                        connectAppRemote(showAuthView = false, result = result)
                    }
                }
            }

            "renewSession" -> silentRenew(result)

            // Reuse the stored token — never shows the auth view, so a silent
            // reconnect can't app-switch the user into Spotify.
            "connectWithToken" -> {
                clientId = call.argument<String>("clientId") ?: clientId
                redirectUrl = call.argument<String>("redirectUrl") ?: redirectUrl
                val token = call.argument<String>("accessToken")
                if (!token.isNullOrEmpty()) accessToken = token
                pendingSpotifyUri = call.argument<String>("spotifyUri") ?: ""
                authRetryAttempted = false
                connectAppRemote(showAuthView = false, result = result)
            }

            "connectAndAuthorize" -> {
                clientId = call.argument<String>("clientId") ?: clientId
                redirectUrl = call.argument<String>("redirectUrl") ?: redirectUrl
                pendingSpotifyUri = call.argument<String>("spotifyUri") ?: ""
                if (spotifyAppRemote?.isConnected == true) {
                    playPendingUri()
                    result.success(true)
                } else {
                    beginAuthorization(result)
                }
            }

            "disconnect" -> {
                spotifyAppRemote?.let { SpotifyAppRemote.disconnect(it) }
                spotifyAppRemote = null
                emit(mapOf("event" to "disconnected"))
                result.success(null)
            }

            "isConnected" -> result.success(spotifyAppRemote?.isConnected ?: false)

            "getAccessToken" -> {
                val token = accessToken
                if (token.isNullOrEmpty()) {
                    result.error("NO_TOKEN", "No Spotify access token available", null)
                } else {
                    result.success(token)
                }
            }

            // Spotify Free cannot play a single track URI on demand; it can
            // still play a playlist/album context. Callers use this to choose
            // which UI to offer instead of failing at play() time.
            "getCapabilities" -> {
                val api = spotifyAppRemote?.userApi
                if (api == null) {
                    result.error("NOT_CONNECTED", "Not connected to Spotify", null)
                } else {
                    api.capabilities
                        .setResultCallback { caps ->
                            result.success(mapOf("canPlayOnDemand" to caps.canPlayOnDemand))
                        }
                        .setErrorCallback { e ->
                            result.error("SPOTIFY_ERROR", e.message, null)
                        }
                }
            }

            "play" -> {
                val uri = call.argument<String>("spotifyUri") ?: ""
                playback(result) { it.play(uri) }
            }

            "pause" -> playback(result) { it.pause() }

            "resume" -> playback(result) { it.resume() }

            "skipNext" -> playback(result) { it.skipNext() }

            "skipPrevious" -> playback(result) { it.skipPrevious() }

            "seekTo" -> {
                val ms = call.argument<Int>("positionMs")?.toLong() ?: 0L
                playback(result) { it.seekTo(ms) }
            }

            "setShuffle" -> {
                val enabled = call.argument<Boolean>("shuffle") ?: false
                playback(result) { it.setShuffle(enabled) }
            }

            "setRepeatMode" -> {
                val mode = call.argument<Int>("repeatMode") ?: 0
                playback(result) { it.setRepeat(mode) }
            }

            else -> result.notImplemented()
        }
    }

    private inline fun playback(
        result: Result,
        command: (com.spotify.android.appremote.api.PlayerApi) -> com.spotify.protocol.client.CallResult<com.spotify.protocol.types.Empty>
    ) {
        val api = spotifyAppRemote?.playerApi
        if (api == null) {
            result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            return
        }
        command(api)
            .setResultCallback { result.success(null) }
            .setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
    }

    // ── Authorization ─────────────────────────────────────────────────────

    /**
     * Full OAuth via the Spotify auth library. Requests a code when a backend
     * token-swap endpoint is configured (that's the only way to get a refresh
     * token), otherwise falls back to the implicit token grant.
     */
    private fun beginAuthorization(result: Result?) {
        val currentActivity = activity
        if (currentActivity == null) {
            result?.error("NO_ACTIVITY", "Spotify auth requires a foreground Activity", null)
            return
        }
        if (!isSpotifyInstalled()) {
            emit(
                mapOf(
                    "event" to "connectionFailed",
                    "code" to "SPOTIFY_NOT_INSTALLED",
                    "message" to "The Spotify app is not installed"
                )
            )
            result?.error("SPOTIFY_NOT_INSTALLED", "The Spotify app is not installed", null)
            return
        }

        pendingResult = result
        val type = if (tokenSwapURL.isNotEmpty()) {
            AuthorizationResponse.Type.CODE
        } else {
            AuthorizationResponse.Type.TOKEN
        }
        val request = AuthorizationRequest.Builder(clientId, type, redirectUrl)
            .setScopes(storedScopes.toTypedArray())
            .build()
        AuthorizationClient.openLoginActivity(currentActivity, AUTH_REQUEST_CODE, request)
    }

    /**
     * Documented fallback (Android SDK guide, "Method 2"): authorize in the
     * browser instead of through the Spotify app. Used when app-to-app SSO
     * cannot complete — including the first-ever authorization, which App
     * Remote refuses to perform itself ("Explicit user authorization is
     * required"). Completing this once creates the user's grant, after which
     * the normal in-app paths have something to connect against.
     */
    private fun browserAuthorize(result: Result?) {
        val currentActivity = activity
        if (currentActivity == null) {
            result?.error("NO_ACTIVITY", "Spotify auth requires a foreground Activity", null)
            return
        }
        val scheme = redirectUrl.substringBefore("://")
        if (scheme.isEmpty()) {
            result?.error("INVALID_REDIRECT_URL", "Cannot derive scheme from $redirectUrl", null)
            return
        }
        browserRedirectUri = "$scheme://$BROWSER_REDIRECT_HOST"
        pendingResult = result
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CLIENT_ID, clientId)
            .putString(KEY_SWAP_URL, tokenSwapURL)
            .putString(KEY_REFRESH_URL, tokenRefreshURL)
            .putString(KEY_BROWSER_REDIRECT, browserRedirectUri)
            .apply()

        val url = android.net.Uri.parse("https://accounts.spotify.com/authorize").buildUpon()
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("redirect_uri", browserRedirectUri)
            .appendQueryParameter("scope", storedScopes.joinToString(" "))
            .appendQueryParameter("show_dialog", "true")
            .build()

        try {
            currentActivity.startActivity(Intent(Intent.ACTION_VIEW, url))
        } catch (e: Exception) {
            failAuth("NO_BROWSER", e.message ?: "No browser available for Spotify login")
        }
    }

    /** Handles the `<scheme>://spotify-auth?code=…` redirect from the browser. */
    internal fun handleBrowserRedirect(uri: android.net.Uri) {
        val error = uri.getQueryParameter("error")
        if (error != null) {
            failAuth("AUTH_ERROR", error)
            return
        }
        val code = uri.getQueryParameter("code")
        if (code.isNullOrEmpty()) {
            failAuth("AUTH_ERROR", "Redirect contained no authorization code")
            return
        }
        if (tokenSwapURL.isEmpty()) {
            failAuth(
                "NO_TOKEN_SWAP_URL",
                "Authorization succeeded but no tokenSwapURL is configured to exchange the code"
            )
            return
        }
        android.util.Log.i(
            "SpotifyAppRemote",
            "browser code received, swapping at $tokenSwapURL (redirect=$browserRedirectUri)"
        )
        swapCodeForToken(
            code,
            redirectOverride = browserRedirectUri.ifEmpty { null },
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != AUTH_REQUEST_CODE) return false
        val response = AuthorizationClient.getResponse(resultCode, data)
        when (response.type) {
            AuthorizationResponse.Type.TOKEN -> {
                val token = response.accessToken
                if (token.isNullOrEmpty()) {
                    failAuth("AUTH_ERROR", "Authorization returned no access token")
                } else {
                    onToken(token, response.expiresIn, source = "firstAuth")
                }
            }

            AuthorizationResponse.Type.CODE -> {
                swapCodeForToken(response.code)
            }

            AuthorizationResponse.Type.ERROR -> {
                failAuth("AUTH_ERROR", response.error ?: "Authorization failed")
            }

            else -> {
                // EMPTY — the user backed out of the login screen.
                failAuth("AUTH_CANCELLED", "Authorization was cancelled")
            }
        }
        return true
    }

    /**
     * Silent renewal — refreshes through the backend without any app switch.
     * Mirrors the iOS clientOnly path, including the `NO_SESSION` code Dart
     * uses to detect "never logged in on this device".
     */
    private fun silentRenew(result: Result) {
        val token = refreshToken
        if (token.isNullOrEmpty() || tokenRefreshURL.isEmpty()) {
            result.error("NO_SESSION", "No stored Spotify session to renew", null)
            return
        }
        pendingResult = result
        postForm(
            tokenRefreshURL,
            mapOf("grant_type" to "refresh_token", "refresh_token" to token)
        ) { json, error ->
            if (json == null) {
                failAuth("TOKEN_EXPIRED", error ?: "Token refresh failed")
                return@postForm
            }
            val fresh = json.optString("access_token", "")
            if (fresh.isEmpty()) {
                failAuth("TOKEN_EXPIRED", "Refresh response contained no access_token")
                return@postForm
            }
            json.optString("refresh_token", "").takeIf { it.isNotEmpty() }?.let(::persistRefresh)
            onToken(fresh, json.optInt("expires_in", 3600), source = "silentRefresh")
        }
    }

    private fun swapCodeForToken(code: String?, redirectOverride: String? = null) {
        if (code.isNullOrEmpty()) {
            failAuth("AUTH_ERROR", "Authorization returned no code")
            return
        }
        postForm(
            tokenSwapURL,
            mapOf(
                "grant_type" to "authorization_code",
                "code" to code,
                "redirect_uri" to (redirectOverride ?: redirectUrl)
            )
        ) { json, error ->
            android.util.Log.i("SpotifyAppRemote", "token swap response json=${json != null} err=$error")
            if (json == null) {
                failAuth("AUTH_ERROR", error ?: "Token swap failed")
                return@postForm
            }
            val token = json.optString("access_token", "")
            if (token.isEmpty()) {
                failAuth("AUTH_ERROR", "Token swap response contained no access_token")
                return@postForm
            }
            json.optString("refresh_token", "").takeIf { it.isNotEmpty() }?.let(::persistRefresh)
            onToken(token, json.optInt("expires_in", 3600), source = "firstAuth")
        }
    }

    /** A token arrived — publish it to Dart, then connect App Remote silently. */
    private fun onToken(token: String, expiresIn: Int, source: String) {
        android.util.Log.i("SpotifyAppRemote", "onToken source=$source len=${token.length}")
        accessToken = token
        emit(
            mapOf(
                "event" to "accessToken",
                "accessToken" to token,
                "expiresIn" to expiresIn,
                "source" to source
            )
        )
        // Playback may already be connected (Android connects first); only
        // connect here if it isn't, and never surface an auth view for a token
        // that is already granted.
        if (spotifyAppRemote?.isConnected != true) {
            connectAppRemote(showAuthView = false, result = pendingResult)
        } else {
            pendingResult?.success(true)
        }
        pendingResult = null
    }

    private fun failAuth(code: String, message: String) {
        // A token failure while App Remote is already connected is not fatal:
        // playback still works, only Web API calls are unavailable. Try the
        // documented browser flow once before giving the token up.
        if (spotifyAppRemote?.isConnected == true && pendingResult == null) {
            if (!browserAuthAttempted) {
                browserAuthAttempted = true
                android.util.Log.w("SpotifyAppRemote", "Token via SSO failed ($code) — trying browser")
                browserAuthorize(null)
                return
            }
            android.util.Log.w("SpotifyAppRemote", "Token fetch failed ($code): $message")
            return
        }
        emit(mapOf("event" to "connectionFailed", "code" to code, "message" to message))
        pendingResult?.error(code, message, null)
        pendingResult = null
    }

    private fun persistRefresh(token: String) {
        refreshToken = token
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REFRESH, token)
            .apply()
    }

    // ── App Remote connection ─────────────────────────────────────────────

    private fun connectAppRemote(showAuthView: Boolean, result: Result?) {
        if (spotifyAppRemote?.isConnected == true) {
            playPendingUri()
            result?.success(true)
            return
        }
        if (!isSpotifyInstalled()) {
            emit(
                mapOf(
                    "event" to "connectionFailed",
                    "code" to "SPOTIFY_NOT_INSTALLED",
                    "message" to "The Spotify app is not installed"
                )
            )
            result?.error("SPOTIFY_NOT_INSTALLED", "The Spotify app is not installed", null)
            return
        }

        // Drop any stale remote first — reconnecting over a half-dead one is a
        // known source of spurious failures.
        spotifyAppRemote?.let { SpotifyAppRemote.disconnect(it) }
        spotifyAppRemote = null

        val params = ConnectionParams.Builder(clientId)
            .setRedirectUri(redirectUrl)
            .showAuthView(showAuthView)
            .build()

        SpotifyAppRemote.connect(context, params, object : Connector.ConnectionListener {
            override fun onConnected(remote: SpotifyAppRemote) {
                spotifyAppRemote = remote
                subscribeToPlayerState()
                emit(mapOf("event" to "connected"))
                playPendingUri()
                result?.success(true)

                // Playback is live; now get a Web API token for track lists and
                // search. Sequential, never alongside the connect — two auth
                // flows into Spotify's single-instance activity cancel each other.
                if (accessToken.isNullOrEmpty() && wantsWebApiToken) {
                    wantsWebApiToken = false
                    beginAuthorization(null)
                }
            }

            override fun onFailure(error: Throwable) {
                spotifyAppRemote = null
                val msg = error.message ?: "Connection failed"
                val code = errorCode(error, msg)

                // "Explicit user authorization is required" means the grant is
                // missing or was revoked — including the case where we still
                // hold a stale token for a revoked grant. App Remote cannot
                // create the grant itself (its auth view is a background
                // activity launch, which Android 14+ blocks), so drop the dead
                // token and authorize from our own foreground activity.
                if (code == "AUTH_ERROR" && !authRetryAttempted) {
                    authRetryAttempted = true
                    accessToken = null
                    android.util.Log.i(
                        "SpotifyAppRemote",
                        "connect needs authorization — re-running auth flow"
                    )
                    beginAuthorization(result)
                    return
                }
                if (code == "DISCONNECTED") {
                    emit(mapOf("event" to "disconnected", "message" to msg))
                } else {
                    emit(
                        mapOf(
                            "event" to "connectionFailed",
                            "code" to code,
                            "message" to msg
                        )
                    )
                }
                result?.error(code, msg, null)
            }
        })
    }

    /** Map SDK exceptions onto the same codes the Dart layer expects from iOS. */
    private fun errorCode(error: Throwable, message: String): String = when {
        error.javaClass.simpleName.contains("CouldNotFindSpotifyApp") ||
            message.contains("not installed", ignoreCase = true) -> "SPOTIFY_NOT_INSTALLED"

        error.javaClass.simpleName.contains("NotLoggedIn") ||
            error.javaClass.simpleName.contains("UserNotAuthorized") ||
            message.contains("Explicit user authorization") -> "AUTH_ERROR"

        message.contains("AUTHENTICATION_SERVICE_UNAVAILABLE") -> "TOKEN_EXPIRED"

        error.javaClass.simpleName.contains("SpotifyDisconnected") -> "DISCONNECTED"

        else -> "CONNECTION_FAILED"
    }

    private fun playPendingUri() {
        val uri = pendingSpotifyUri
        pendingSpotifyUri = ""
        if (uri.isEmpty()) return
        spotifyAppRemote?.playerApi?.play(uri)
    }

    private fun isSpotifyInstalled(): Boolean = try {
        context.packageManager.getPackageInfo("com.spotify.music", 0)
        true
    } catch (e: Exception) {
        false
    }

    private fun subscribeToPlayerState() {
        spotifyAppRemote?.playerApi
            ?.subscribeToPlayerState()
            ?.setEventCallback { state: PlayerState ->
                emit(
                    mapOf(
                        "event" to "playerState",
                        "isPaused" to state.isPaused,
                        "trackUri" to (state.track?.uri ?: ""),
                        "trackName" to (state.track?.name ?: ""),
                        "artistName" to (state.track?.artist?.name ?: ""),
                        "albumName" to (state.track?.album?.name ?: ""),
                        "imageIdentifier" to (state.track?.imageUri?.raw ?: ""),
                        "playbackPosition" to state.playbackPosition,
                        "duration" to (state.track?.duration ?: 0L),
                        "isShuffling" to state.playbackOptions.isShuffling,
                        "repeatMode" to state.playbackOptions.repeatMode,
                    )
                )
            }
    }

    // ── Backend token swap/refresh ────────────────────────────────────────

    /**
     * Form-POST to the app's token swap/refresh endpoint. Runs off the main
     * thread; [onDone] is always delivered back on it.
     */
    private fun postForm(
        url: String,
        fields: Map<String, String>,
        onDone: (JSONObject?, String?) -> Unit
    ) {
        io.execute {
            var connection: HttpURLConnection? = null
            try {
                val body = fields.entries.joinToString("&") { (k, v) ->
                    "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
                }
                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    setRequestProperty(
                        "Content-Type",
                        "application/x-www-form-urlencoded; charset=UTF-8"
                    )
                }
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                val code = connection.responseCode
                val stream = if (code in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use(BufferedReader::readText) ?: ""
                if (code !in 200..299) {
                    main.post { onDone(null, "HTTP $code: $text") }
                    return@execute
                }
                val json = JSONObject(text)
                main.post { onDone(json, null) }
            } catch (e: Exception) {
                main.post { onDone(null, e.message ?: "Network error") }
            } finally {
                connection?.disconnect()
            }
        }
    }

    // ── Event channel ─────────────────────────────────────────────────────

    private fun emit(data: Map<String, Any?>) {
        main.post { eventSink?.success(data) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
