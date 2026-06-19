package com.spotifyappremote.spotify_app_remote

import android.content.Context
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.protocol.types.PlayerState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Flutter plugin wrapping the Spotify Android App Remote SDK. */
class SpotifyAppRemotePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var eventSink: EventChannel.EventSink? = null
    private var spotifyAppRemote: SpotifyAppRemote? = null

    companion object {
        const val METHOD_CHANNEL = "com.spotifyappremote/method"
        const val EVENT_CHANNEL  = "com.spotifyappremote/events"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context       = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel  = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        spotifyAppRemote?.let { SpotifyAppRemote.disconnect(it) }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {

            // Android App Remote SDK handles auth internally — both connect methods
            // use the same flow; no separate token needed on Android.
            "connectWithToken",
            "connectAndAuthorize" -> {
                val clientId    = call.argument<String>("clientId")    ?: ""
                val redirectUrl = call.argument<String>("redirectUrl") ?: ""
                connect(clientId, redirectUrl, result)
            }

            "disconnect" -> {
                spotifyAppRemote?.let { SpotifyAppRemote.disconnect(it) }
                spotifyAppRemote = null
                result.success(null)
            }

            "isConnected" ->
                result.success(spotifyAppRemote?.isConnected ?: false)

            "getAccessToken" ->
                result.error(
                    "NOT_SUPPORTED",
                    "getAccessToken is not available on Android App Remote SDK",
                    null
                )

            "play" -> {
                val uri = call.argument<String>("spotifyUri") ?: ""
                spotifyAppRemote?.playerApi?.play(uri)
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "pause" -> {
                spotifyAppRemote?.playerApi?.pause()
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "resume" -> {
                spotifyAppRemote?.playerApi?.resume()
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "skipNext" -> {
                spotifyAppRemote?.playerApi?.skipNext()
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "skipPrevious" -> {
                spotifyAppRemote?.playerApi?.skipPrevious()
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "seekTo" -> {
                val ms = call.argument<Int>("positionMs")?.toLong() ?: 0L
                spotifyAppRemote?.playerApi?.seekTo(ms)
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "setShuffle" -> {
                val enabled = call.argument<Boolean>("shuffle") ?: false
                spotifyAppRemote?.playerApi?.setShuffle(enabled)
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            "setRepeatMode" -> {
                val mode = call.argument<Int>("repeatMode") ?: 0
                spotifyAppRemote?.playerApi?.setRepeat(mode)
                    ?.setResultCallback { result.success(null) }
                    ?.setErrorCallback { e -> result.error("SPOTIFY_ERROR", e.message, null) }
                    ?: result.error("NOT_CONNECTED", "Not connected to Spotify", null)
            }

            else -> result.notImplemented()
        }
    }

    private fun connect(clientId: String, redirectUrl: String, result: Result) {
        val params = ConnectionParams.Builder(clientId)
            .setRedirectUri(redirectUrl)
            .showAuthView(true)
            .build()

        SpotifyAppRemote.connect(context, params, object : Connector.ConnectionListener {
            override fun onConnected(remote: SpotifyAppRemote) {
                spotifyAppRemote = remote
                subscribeToPlayerState()
                emit(mapOf("event" to "connected"))
                result.success(true)
            }

            override fun onFailure(error: Throwable) {
                val msg  = error.message ?: "Connection failed"
                val code = if (msg.contains("AUTHENTICATION_SERVICE_UNAVAILABLE"))
                    "TOKEN_EXPIRED" else "CONNECTION_FAILED"
                emit(mapOf("event" to "connectionFailed", "code" to code, "message" to msg))
                result.error(code, msg, null)
            }
        })
    }

    private fun subscribeToPlayerState() {
        spotifyAppRemote?.playerApi
            ?.subscribeToPlayerState()
            ?.setEventCallback { state: PlayerState ->
                emit(
                    mapOf(
                        "event"            to "playerState",
                        "isPaused"         to state.isPaused,
                        "trackUri"         to (state.track?.uri            ?: ""),
                        "trackName"        to (state.track?.name           ?: ""),
                        "artistName"       to (state.track?.artist?.name   ?: ""),
                        "albumName"        to (state.track?.album?.name    ?: ""),
                        "imageIdentifier"  to (state.track?.imageUri?.raw  ?: ""),
                        "playbackPosition" to state.playbackPosition,
                        "duration"         to (state.track?.duration       ?: 0L),
                        "isShuffling"      to state.playbackOptions.isShuffling,
                        "repeatMode"       to state.playbackOptions.repeatMode,
                    )
                )
            }
    }

    private fun emit(data: Map<String, Any?>) {
        eventSink?.success(data)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
