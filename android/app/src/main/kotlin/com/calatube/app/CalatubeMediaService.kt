package com.calatube.app

import android.app.*
import android.content.*
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.*
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import kotlinx.coroutines.*
import java.net.URL

class CalatubeMediaService : Service() {

    companion object {
        const val CHANNEL_ID   = "calatube_media"
        const val NOTIF_ID     = 42
        const val ACTION_PLAY  = "com.calatube.PLAY"
        const val ACTION_PAUSE = "com.calatube.PAUSE"
        const val ACTION_NEXT  = "com.calatube.NEXT"
        const val ACTION_PREV  = "com.calatube.PREV"
        var webViewRef: android.webkit.WebView? = null
    }

    private val binder        = LocalBinder()
    private var mediaSession  : MediaSessionCompat? = null
    private var notifManager  : NotificationManager? = null
    private val stateBuilder  = PlaybackStateCompat.Builder()
    private val scope         = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var audioManager  : AudioManager? = null
    private var focusRequest  : AudioFocusRequest? = null
    private var isPlaying     = false
    private var currentTitle  = ""
    private var currentArtist = ""
    private var currentArt    : Bitmap? = null

    inner class LocalBinder : Binder() {
        fun getService() = this@CalatubeMediaService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        setupMediaSession()
        setupNotificationChannel()
        // Démarrer immédiatement en foreground avec une notif vide
        startForeground(NOTIF_ID, buildNotification("Calatube", "", null, false))
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "CalatubeSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    requestAudioFocus()
                    jsCall("NouTube.play()")
                    updatePlayState(true)
                }
                override fun onPause() {
                    jsCall("NouTube.pause()")
                    updatePlayState(false)
                }
                override fun onSkipToNext()     { jsCall("NouTube.next()") }
                override fun onSkipToPrevious() { jsCall("NouTube.prev()") }
                override fun onStop()           { jsCall("NouTube.pause()"); updatePlayState(false) }
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

    private fun requestAudioFocus() {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> {
                        jsCall("NouTube.pause()")
                        updatePlayState(false)
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                        jsCall("NouTube.pause()")
                        updatePlayState(false)
                    }
                }
            }
            .build()
        focusRequest?.let { audioManager?.requestAudioFocus(it) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY  -> { requestAudioFocus(); jsCall("NouTube.play()");  updatePlayState(true) }
            ACTION_PAUSE -> { jsCall("NouTube.pause()"); updatePlayState(false) }
            ACTION_NEXT  -> jsCall("NouTube.next()")
            ACTION_PREV  -> jsCall("NouTube.prev()")
            else         -> MediaButtonReceiver.handleIntent(mediaSession, intent)
        }
        return START_STICKY
    }

    private fun jsCall(script: String) {
        Handler(Looper.getMainLooper()).post {
            webViewRef?.evaluateJavascript(script, null)
        }
    }

    fun updateNotification(
        title: String, artist: String,
        thumbUrl: String, playing: Boolean, durationMs: Long = 0
    ) {
        isPlaying     = playing
        currentTitle  = title
        currentArtist = artist
        if (playing) requestAudioFocus()

        scope.launch {
            // Charger la miniature
            var bitmap = currentArt
            if (thumbUrl.isNotEmpty()) {
                try {
                    val stream = URL(thumbUrl).openStream()
                    bitmap = BitmapFactory.decodeStream(stream)
                    currentArt = bitmap
                } catch (_: Exception) {}
            }

            val meta = MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
                .build()
            mediaSession?.setMetadata(meta)
            updatePlayStateInternal(playing, 0)

            withContext(Dispatchers.Main) {
                val notif = buildNotification(title, artist, bitmap, playing)
                startForeground(NOTIF_ID, notif)
                notifManager?.notify(NOTIF_ID, notif)
            }
        }
    }

    fun updatePlayState(playing: Boolean, posMs: Long = 0) {
        isPlaying = playing
        updatePlayStateInternal(playing, posMs)
        val notif = buildNotification(currentTitle, currentArtist, currentArt, playing)
        notifManager?.notify(NOTIF_ID, notif)
        if (playing) {
            startForeground(NOTIF_ID, notif)
        } else {
            stopForeground(STOP_FOREGROUND_DETACH)
        }
    }

    private fun updatePlayStateInternal(playing: Boolean, posMs: Long) {
        val state = stateBuilder
            .setState(
                if (playing) PlaybackStateCompat.STATE_PLAYING
                else         PlaybackStateCompat.STATE_PAUSED,
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
    }

    private fun buildNotification(
        title: String, artist: String,
        art: Bitmap?, playing: Boolean
    ): Notification {
        val session = mediaSession!!
        val intent  = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun pi(action: String, code: Int) = PendingIntent.getService(
            this, code,
            Intent(this, CalatubeMediaService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(art)
            .setContentTitle(title.ifEmpty { "Calatube" })
            .setContentText(artist)
            .setContentIntent(pending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setSilent(true)
            .addAction(NotificationCompat.Action(R.drawable.ic_prev, "Précédent", pi(ACTION_PREV, 1)))
            .addAction(NotificationCompat.Action(
                if (playing) R.drawable.ic_pause else R.drawable.ic_play,
                if (playing) "Pause" else "Lecture",
                pi(if (playing) ACTION_PAUSE else ACTION_PLAY, 2)))
            .addAction(NotificationCompat.Action(R.drawable.ic_next, "Suivant", pi(ACTION_NEXT, 3)))
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    override fun onDestroy() {
        scope.cancel()
        focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        mediaSession?.release()
        super.onDestroy()
    }
}
