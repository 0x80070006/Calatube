package com.calatube.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaService: CalatubeMediaService? = null
    private var serviceBound = false
    private val CHANNEL = "com.calatube.app/media"

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            mediaService = (binder as CalatubeMediaService.LocalBinder).getService()
            serviceBound = true
        }
        override fun onServiceDisconnected(name: ComponentName) {
            serviceBound = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Démarrer et binder le service
        val intent = Intent(this, CalatubeMediaService::class.java)
        startService(intent)
        bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Activer cookies pour YouTube Music
        val cookieManager = android.webkit.CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        // Canal Flutter ↔ Android pour les infos de lecture
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateNowPlaying" -> {
                        val title    = call.argument<String>("title") ?: ""
                        val artist   = call.argument<String>("artist") ?: ""
                        val thumb    = call.argument<String>("thumb") ?: ""
                        val playing  = call.argument<Boolean>("playing") ?: false
                        val duration = (call.argument<Any>("duration") as? Number)?.toLong() ?: 0L
                        mediaService?.updateNotification(title, artist, thumb, playing, duration)
                        result.success(null)
                    }
                    "updatePlayState" -> {
                        val playing = call.argument<Boolean>("playing") ?: false
                        val pos     = (call.argument<Any>("pos") as? Number)?.toLong() ?: 0L
                        mediaService?.updatePlayState(playing, pos)
                        result.success(null)
                    }
                    "setWebView" -> {
                        // La WebView Flutter est gérée côté Dart — pas besoin ici
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (serviceBound) unbindService(connection)
        super.onDestroy()
    }
}
