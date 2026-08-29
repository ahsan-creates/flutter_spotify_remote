package com.spotifyappremote.spotify_app_remote

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Receives the OAuth redirect for the browser authorization flow.
 *
 * Spotify's own auth library owns the primary redirect URI (used by its
 * app-to-app SSO), so the browser flow needs a second, distinct URI —
 * `<scheme>://spotify-auth` — with a receiver we control end to end. Routing
 * it through the library's receiver instead drops the authorization code,
 * because its LoginActivity has no caller to return a result to.
 *
 * Declared translucent and no-history so it never appears in the back stack.
 */
class SpotifyBrowserAuthActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deliver(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        deliver(intent)
    }

    private fun deliver(intent: Intent?) {
        val data = intent?.data
        android.util.Log.i("SpotifyBrowserAuth", "redirect received: data=$data")
        if (data != null) SpotifyAppRemotePlugin.onBrowserRedirect(data)
        finish()
    }
}
