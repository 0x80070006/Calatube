package com.calatube.app

import android.app.*
import android.bluetooth.BluetoothDevice
import android.content.*
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.os.*
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import kotlinx.coroutines.*
import java.net.URL

class NoisyReceiver(private val service: CalatubeMediaService) : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY ||
            intent.action == BluetoothDevice.ACTION_ACL_DISCONNECTED) {
            service.pauseFromNative()
        }
    }
}

class CalatubeMediaService : Service() {

    companion object {
        const val CHANNEL_ID = "calatube_media"
        const val NOTIF_ID   = 42
        const val ACTION_PLAY  = "com.calatube.PLAY"
        const val ACTION_PAUSE = "com.calatube.PAUSE"
        const val ACTION_NEXT  = "com.calatube.NEXT"
        const val ACTION_PREV  = "com.calatube.PREV"

        // Référence statique à la WebView pour les callbacks JS
        var webViewRef: android.webkit.WebView? = null
    }

    private val binder = LocalBinder()
    private var mediaSession: MediaSessionCompat? = null
    private var notifManager: NotificationManager? = null
    private var stateBuilder = PlaybackStateCompat.Builder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var noisyReceiver: NoisyReceiver? = null

    inner class LocalBinder : Binder() {
        fun getService() = this@CalatubeMediaService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        setupMediaSession()
        setupNotificationChannel()
        registerNoisyReceiver()
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "CalatubeSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay()           { jsCall("NouTube.play()");  updatePlayState(true) }
                override fun onPause()          { jsCall("NouTube.pause()"); updatePlayState(false) }
                override fun onSkipToNext()     { jsCall("NouTube.next()") }
                override fun onSkipToPrevious() { jsCall("NouTube.prev()") }
            })
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            isActive = true
        }
    }

    private fun setupNotificationChannel() {
        notifManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID, "Calatube — Lecture en cours",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            setShowBadge(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notifManager?.createNotificationChannel(channel)
    }

    private fun registerNoisyReceiver() {
        noisyReceiver = NoisyReceiver(this)
        val filter = IntentFilter().apply {
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        }
        registerReceiver(noisyReceiver, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY  -> { jsCall("NouTube.play()");  updatePlayState(true) }
            ACTION_PAUSE -> { jsCall("NouTube.pause()"); updatePlayState(false) }
            ACTION_NEXT  -> jsCall("NouTube.next()")
            ACTION_PREV  -> jsCall("NouTube.prev()")
            else         -> MediaButtonReceiver.handleIntent(mediaSession, intent)
        }
        return START_STICKY
    }

    fun pauseFromNative() {
        jsCall("NouTube.pause()")
        updatePlayState(false)
    }

    private fun jsCall(script: String) {
        Handler(Looper.getMainLooper()).post {
            webViewRef?.evaluateJavascript(script, null)
        }
    }

    fun updateNotification(
        title: String, artist: String,
        thumbUrl: String, isPlaying: Boolean, durationMs: Long = 0
    ) {
        scope.launch {
            val metaBuilder = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

            // Charger la miniature en arrière-plan
            var bitmap = BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
            if (thumbUrl.isNotEmpty()) {
                try {
                    val stream = URL(thumbUrl).openStream()
                    bitmap = BitmapFactory.decodeStream(stream)
                } catch (_: Exception) {}
            }
            metaBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
            mediaSession?.setMetadata(metaBuilder.build())

            updatePlayState(isPlaying)

            val notification = buildNotification(title, artist, bitmap, isPlaying)
            withContext(Dispatchers.Main) {
                startForeground(NOTIF_ID, notification)
                notifManager?.notify(NOTIF_ID, notification)
            }
        }
    }

    fun updatePlayState(isPlaying: Boolean, posMs: Long = 0) {
        val state = stateBuilder
            .setState(
                if (isPlaying) PlaybackStateCompat.STATE_PLAYING
                else           PlaybackStateCompat.STATE_PAUSED,
                posMs, 1f
            )
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
            )
            .build()
        mediaSession?.setPlaybackState(state)
        // Mettre à jour la notification si elle existe déjà
        val meta = mediaSession?.controller?.metadata ?: return
        val title  = meta.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: return
        val artist = meta.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: ""
        val art    = meta.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART)
        val notif  = buildNotification(title, artist, art, isPlaying)
        notifManager?.notify(NOTIF_ID, notif)
    }

    private fun buildNotification(
        title: String, artist: String,
        art: android.graphics.Bitmap?,
        isPlaying: Boolean
    ): Notification {
        val session = mediaSession!!
        val intent  = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun actionPending(action: String, reqCode: Int) = PendingIntent.getService(
            this, reqCode,
            Intent(this, CalatubeMediaService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(art)
            .setContentTitle(title)
            .setContentText(artist)
            .setContentIntent(pending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .setSilent(true)
            .addAction(NotificationCompat.Action(
                R.drawable.ic_prev, "Précédent",
                actionPending(ACTION_PREV, 1)))
            .addAction(NotificationCompat.Action(
                if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play,
                if (isPlaying) "Pause" else "Lecture",
                actionPending(if (isPlaying) ACTION_PAUSE else ACTION_PLAY, 2)))
            .addAction(NotificationCompat.Action(
                R.drawable.ic_next, "Suivant",
                actionPending(ACTION_NEXT, 3)))
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    override fun onDestroy() {
        scope.cancel()
        mediaSession?.release()
        try { noisyReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        super.onDestroy()
    }
}
