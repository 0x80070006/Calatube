package com.calatube.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity
 *
 * Responsabilités :
 *  1. Démarrer CalatubeMediaService en foreground
 *  2. Binder au service pour lui injecter le commandCallback
 *  3. Exposer un MethodChannel "com.calatube.app/media" côté Dart
 *     - Dart → Android : updateNowPlaying, updateProgress
 *     - Android → Dart : mediaCommand (play/pause/next/prev/seek)
 *  4. Rebinder automatiquement si le service redémarre (START_STICKY)
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG     = "CalatubeMain"
        const val CHANNEL         = "com.calatube.app/media"
    }

    // ─────────────────────────────────────────────────────────────
    // MethodChannel (initialisé dans configureFlutterEngine)
    // ─────────────────────────────────────────────────────────────
    private var methodChannel: MethodChannel? = null

    // ─────────────────────────────────────────────────────────────
    // Service binding
    // ─────────────────────────────────────────────────────────────
    private var mediaService : CalatubeMediaService? = null
    private var serviceBound  = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            Log.d(TAG, "ServiceConnected")
            mediaService = (binder as CalatubeMediaService.LocalBinder).getService()
            serviceBound  = true
            injectCommandCallback()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            Log.w(TAG, "ServiceDisconnected")
            mediaService = null
            serviceBound  = false
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Activer les cookies WebView (nécessaire pour la connexion Google)
        try {
            android.webkit.CookieManager.getInstance().apply {
                setAcceptCookie(true)
                setAcceptThirdPartyCookies(
                    // WebView Flutter utilise ce flag pour music.youtube.com
                    null, true
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "CookieManager init: ${e.message}")
        }

        startMediaService()
        bindMediaService()
    }

    override fun onDestroy() {
        if (serviceBound) {
            try { unbindService(serviceConnection) } catch (e: Exception) {
                Log.w(TAG, "unbindService: ${e.message}")
            }
            serviceBound = false
        }
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────
    // Service
    // ─────────────────────────────────────────────────────────────
    private fun startMediaService() {
        val intent = Intent(this, CalatubeMediaService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun bindMediaService() {
        try {
            val intent = Intent(this, CalatubeMediaService::class.java)
            bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        } catch (e: Exception) {
            Log.e(TAG, "bindMediaService: ${e.message}")
        }
    }

    /**
     * Injecte le callback qui relaie les commandes Android → Dart.
     * Appelé dès que le binding est établi (et re-établi si service redémarre).
     */
    private fun injectCommandCallback() {
        mediaService?.commandCallback = { cmd, arg ->
            // On est potentiellement sur un thread background → runOnUiThread
            runOnUiThread {
                try {
                    methodChannel?.invokeMethod(
                        "mediaCommand",
                        mapOf("cmd" to cmd, "arg" to arg)
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "invokeMethod mediaCommand: ${e.message}")
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Flutter Engine / MethodChannel
    // ─────────────────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {

                        // ── Dart → Service : nouvelle piste ─────────────────
                        "updateNowPlaying" -> {
                            try {
                                val title    = call.argument<String>("title")   ?: ""
                                val artist   = call.argument<String>("artist")  ?: ""
                                val thumb    = call.argument<String>("thumb")   ?: ""
                                val playing  = call.argument<Boolean>("playing") ?: false
                                // JS envoie la durée en secondes
                                val durSec   = (call.argument<Any>("duration") as? Number)
                                    ?.toLong() ?: 0L
                                mediaService?.onNowPlaying(title, artist, thumb, playing, durSec)
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(TAG, "updateNowPlaying: ${e.message}")
                                result.error("ERR_NOW_PLAYING", e.message, null)
                            }
                        }

                        // ── Dart → Service : progression ────────────────────
                        "updateProgress" -> {
                            try {
                                val playing  = call.argument<Boolean>("playing") ?: false
                                // JS envoie la position en secondes
                                val posSec   = (call.argument<Any>("pos") as? Number)
                                    ?.toLong() ?: 0L
                                mediaService?.onProgress(playing, posSec)
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(TAG, "updateProgress: ${e.message}")
                                result.error("ERR_PROGRESS", e.message, null)
                            }
                        }

                        else -> result.notImplemented()
                    }
                }
            }

        // Si le service est déjà bindé, injecter le callback maintenant
        if (serviceBound) injectCommandCallback()
    }
}
