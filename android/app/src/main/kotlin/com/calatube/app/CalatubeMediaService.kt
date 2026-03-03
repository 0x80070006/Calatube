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
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import kotlinx.coroutines.*
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * CalatubeMediaService — Service foreground MediaStyle
 *
 * Architecture :
 *  - Foreground service (survit à la mise en veille et à la minimisation)
 *  - MediaSession avec callbacks relayés vers la WebView via MethodChannel
 *  - AudioFocus : pause auto si appel téléphonique, reprise si possible
 *  - WakeLock PARTIAL : empêche le CPU de s'endormir pendant la lecture
 *  - Cache bitmap : l'artwork n'est re-téléchargé que si l'URL change
 *  - Seek : ACTION_SEEK_TO relayé au JS → curseur glissable
 *  - Position mise à jour toutes les secondes via Handler
 */
class CalatubeMediaService : Service() {

    // ─────────────────────────────────────────────────────────────
    // Companion / constantes
    // ─────────────────────────────────────────────────────────────
    companion object {
        const val CHANNEL_ID    = "calatube_media_v2"
        const val NOTIF_ID      = 1
        const val ACTION_PLAY   = "com.calatube.app.PLAY"
        const val ACTION_PAUSE  = "com.calatube.app.PAUSE"
        const val ACTION_NEXT   = "com.calatube.app.NEXT"
        const val ACTION_PREV   = "com.calatube.app.PREV"
        const val ACTION_SEEK   = "com.calatube.app.SEEK"
        const val EXTRA_SEEK_MS = "seek_ms"
        private const val TAG   = "CalatubeService"

        // Durée entre deux updates de position (ms)
        private const val POSITION_TICK_MS = 1_000L
        // Timeout réseau pour le téléchargement de l'artwork (ms)
        private const val ART_CONNECT_TIMEOUT_MS = 5_000
        private const val ART_READ_TIMEOUT_MS    = 8_000
    }

    // ─────────────────────────────────────────────────────────────
    // Binder
    // ─────────────────────────────────────────────────────────────
    inner class LocalBinder : Binder() {
        fun getService(): CalatubeMediaService = this@CalatubeMediaService
    }

    private val binder = LocalBinder()
    override fun onBind(intent: Intent): IBinder = binder

    // ─────────────────────────────────────────────────────────────
    // État interne
    // ─────────────────────────────────────────────────────────────
    private var mediaSession  : MediaSessionCompat? = null
    private var notifManager  : NotificationManager? = null
    private var audioManager  : AudioManager? = null
    private var focusRequest  : AudioFocusRequest? = null
    private var wakeLock      : PowerManager.WakeLock? = null

    // Coroutines
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var artJob: Job? = null   // job de chargement de l'artwork (annulable)

    // État de lecture
    @Volatile private var isPlaying    = false
    @Volatile private var positionMs   = 0L
    @Volatile private var durationMs   = 0L

    // Métadonnées
    @Volatile private var currentTitle  = ""
    @Volatile private var currentArtist = ""
    @Volatile private var currentThumb  = ""   // URL en cache
    @Volatile private var currentArt   : Bitmap? = null

    // PlaybackState builder (réutilisé)
    private val stateBuilder = PlaybackStateCompat.Builder()

    // Handler pour ticker la position
    private val mainHandler = Handler(Looper.getMainLooper())
    private val positionTicker = object : Runnable {
        override fun run() {
            if (isPlaying) {
                positionMs += POSITION_TICK_MS
                pushPlaybackState()
                updateNotificationQuiet()
            }
            mainHandler.postDelayed(this, POSITION_TICK_MS)
        }
    }

    // Callback de commande vers Flutter (injecté par MainActivity)
    var commandCallback: ((String, Long) -> Unit)? = null

    // ─────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")

        audioManager  = getSystemService(AUDIO_SERVICE) as AudioManager
        notifManager  = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        acquireWakeLock()
        createNotificationChannel()
        setupMediaSession()

        // Démarrer immédiatement en foreground (requis Android 12+)
        startForeground(NOTIF_ID, buildNotification())
        mainHandler.postDelayed(positionTicker, POSITION_TICK_MS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")

        when (intent?.action) {
            ACTION_PLAY  -> handlePlay()
            ACTION_PAUSE -> handlePause()
            ACTION_NEXT  -> dispatchCommand("next", 0L)
            ACTION_PREV  -> dispatchCommand("prev", 0L)
            ACTION_SEEK  -> {
                val ms = intent.getLongExtra(EXTRA_SEEK_MS, -1L)
                if (ms >= 0) handleSeek(ms)
            }
            else -> mediaSession?.let { MediaButtonReceiver.handleIntent(it, intent) }
        }

        // START_NOT_STICKY : ne pas redémarrer si tué depuis le gestionnaire de tâches
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // L'utilisateur a fermé l'app depuis le gestionnaire de tâches → arrêt propre
        Log.d(TAG, "onTaskRemoved → stopSelf")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        mainHandler.removeCallbacks(positionTicker)
        scope.cancel()
        releaseAudioFocus()
        releaseWakeLock()
        mediaSession?.apply {
            isActive = false
            release()
        }
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────
    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Calatube::MediaWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire(/* 12h max */ 12 * 60 * 60 * 1_000L)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            Log.w(TAG, "releaseWakeLock: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Calatube — Lecture",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description             = "Contrôles de lecture Calatube"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility    = Notification.VISIBILITY_PUBLIC
        }
        notifManager?.createNotificationChannel(channel)
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "CalatubeSession").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )

            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay()  { handlePlay() }
                override fun onPause() { handlePause() }
                override fun onStop()  { handlePause() }

                override fun onSkipToNext()     { dispatchCommand("next", 0L) }
                override fun onSkipToPrevious() { dispatchCommand("prev", 0L) }

                override fun onSeekTo(posMs: Long) { handleSeek(posMs) }
            })

            // Capabilities déclarées (nécessaire pour le curseur glissable)
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setState(PlaybackStateCompat.STATE_NONE, 0L, 1f)
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY               or
                        PlaybackStateCompat.ACTION_PAUSE              or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE         or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT       or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS   or
                        PlaybackStateCompat.ACTION_SEEK_TO            or
                        PlaybackStateCompat.ACTION_STOP
                    )
                    .build()
            )
            isActive = true
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Actions de lecture
    // ─────────────────────────────────────────────────────────────
    private fun handlePlay() {
        requestAudioFocus()
        dispatchCommand("play", 0L)
        setPlaying(true)
    }

    private fun handlePause() {
        dispatchCommand("pause", 0L)
        setPlaying(false)
    }

    private fun handleSeek(posMs: Long) {
        positionMs = posMs.coerceIn(0L, if (durationMs > 0) durationMs else Long.MAX_VALUE)
        dispatchCommand("seek", positionMs)
        pushPlaybackState()
        updateNotificationQuiet()
    }

    private fun setPlaying(playing: Boolean) {
        isPlaying = playing
        pushPlaybackState()
        // Foreground obligatoire pendant la lecture
        val notif = buildNotification()
        if (playing) {
            startForeground(NOTIF_ID, notif)
        } else {
            stopForeground(STOP_FOREGROUND_DETACH)
            notifManager?.notify(NOTIF_ID, notif)
        }
    }

    /** Envoie une commande vers Flutter (play/pause/next/prev/seek). */
    private fun dispatchCommand(cmd: String, arg: Long) {
        try {
            commandCallback?.invoke(cmd, arg)
        } catch (e: Exception) {
            Log.e(TAG, "dispatchCommand($cmd): ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Audio Focus
    // ─────────────────────────────────────────────────────────────
    private fun requestAudioFocus() {
        // Ne pas re-demander si on a déjà le focus
        if (focusRequest != null) return

        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setAcceptsDelayedFocusGain(true)
            // On gère le ducking nous-mêmes → on ne pause pas pour DUCK
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener { focus ->
                when (focus) {
                    AudioManager.AUDIOFOCUS_LOSS,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        // On ignore tous les LOSS.
                        // Re-demander le focus causerait un LOSS sur Chromium (WebView)
                        // qui couperait la lecture → boucle infinie skip.
                        Log.d(TAG, "AudioFocus LOSS($focus) → ignoré")
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        Log.d(TAG, "AudioFocus GAIN")
                    }
                }
            }
            .build()

        val result = audioManager?.requestAudioFocus(focusRequest!!)
        Log.d(TAG, "AudioFocus requested, result=$result")
    }

    private fun releaseAudioFocus() {
        try {
            focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } catch (e: Exception) {
            Log.w(TAG, "releaseAudioFocus: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────
    // API publique (appelée depuis MainActivity via le binder)
    // ─────────────────────────────────────────────────────────────

    /**
     * Met à jour les métadonnées (titre, artiste, artwork, durée).
     * Déclenché par le bridge JS → Dart → MethodChannel → Service.
     * @param durationSec durée en SECONDES (tel qu'envoyé par le JS)
     */
    fun onNowPlaying(
        title: String,
        artist: String,
        thumbUrl: String,
        playing: Boolean,
        durationSec: Long
    ) {
        Log.d(TAG, "onNowPlaying title=$title playing=$playing dur=${durationSec}s")

        val titleChanged  = (title != currentTitle || artist != currentArtist)
        currentTitle   = title.ifEmpty { "Calatube" }
        currentArtist  = artist
        durationMs     = durationSec * 1_000L   // conversion s → ms
        isPlaying      = playing

        if (playing) requestAudioFocus()

        // Charger l'artwork en arrière-plan uniquement si l'URL a changé
        if (thumbUrl != currentThumb) {
            currentThumb = thumbUrl
            artJob?.cancel()
            artJob = scope.launch {
                val bmp = fetchBitmap(thumbUrl)
                currentArt = bmp
                withContext(Dispatchers.Main) {
                    pushMetadata()
                    pushPlaybackState()
                    val notif = buildNotification()
                    if (isPlaying) startForeground(NOTIF_ID, notif)
                    else notifManager?.notify(NOTIF_ID, notif)
                }
            }
        } else {
            // Artwork inchangé, mise à jour immédiate
            pushMetadata()
            pushPlaybackState()
            val notif = buildNotification()
            if (isPlaying) startForeground(NOTIF_ID, notif)
            else notifManager?.notify(NOTIF_ID, notif)
        }
    }

    /**
     * Met à jour la position et l'état play/pause.
     * Appelé régulièrement par le JS (toutes les secondes).
     * @param posSec position en SECONDES
     */
    fun onProgress(playing: Boolean, posSec: Long) {
        val newPosMs = posSec * 1_000L
        val changed  = (isPlaying != playing || Math.abs(newPosMs - positionMs) > 1_500L)
        isPlaying  = playing
        positionMs = newPosMs

        if (changed) {
            pushPlaybackState()
            updateNotificationQuiet()
        }
    }

    // ─────────────────────────────────────────────────────────────
    // MediaSession state + metadata
    // ─────────────────────────────────────────────────────────────
    private fun pushMetadata() {
        val meta = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE,    currentTitle)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST,   currentArtist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM,    "YouTube Music")
            .putLong(  MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, currentArt)
            .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, currentArt)
            .build()
        mediaSession?.setMetadata(meta)
    }

    private fun pushPlaybackState() {
        val state = if (isPlaying) PlaybackStateCompat.STATE_PLAYING
                    else           PlaybackStateCompat.STATE_PAUSED

        mediaSession?.setPlaybackState(
            stateBuilder
                .setState(state, positionMs, 1f)
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY               or
                    PlaybackStateCompat.ACTION_PAUSE              or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE         or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT       or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS   or
                    PlaybackStateCompat.ACTION_SEEK_TO            or
                    PlaybackStateCompat.ACTION_STOP
                )
                .build()
        )
    }

    // ─────────────────────────────────────────────────────────────
    // Notification
    // ─────────────────────────────────────────────────────────────

    /** Rebuild + notify sans toucher au foreground state. */
    private fun updateNotificationQuiet() {
        try {
            notifManager?.notify(NOTIF_ID, buildNotification())
        } catch (e: Exception) {
            Log.w(TAG, "updateNotificationQuiet: ${e.message}")
        }
    }

    private fun buildNotification(): Notification {
        val session = mediaSession ?: return buildFallbackNotification()
        val token   = session.sessionToken

        // Intent d'ouverture de l'app
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openAppPi = PendingIntent.getActivity(
            this, 0, openAppIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun actionPi(action: String, code: Int): PendingIntent =
            PendingIntent.getService(
                this, code,
                Intent(this, CalatubeMediaService::class.java).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        val playPauseIcon   = if (isPlaying) R.drawable.ic_pause  else R.drawable.ic_play
        val playPauseLabel  = if (isPlaying) "Pause"              else "Lecture"
        val playPauseAction = if (isPlaying) ACTION_PAUSE         else ACTION_PLAY

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(currentArt)
            .setContentTitle(currentTitle.ifEmpty { "Calatube" })
            .setContentText(currentArtist.ifEmpty { "YouTube Music" })
            .setContentIntent(openAppPi)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            // ── Actions ──────────────────────────────────────────
            .addAction(NotificationCompat.Action(
                R.drawable.ic_prev, "Précédent", actionPi(ACTION_PREV, 1)))
            .addAction(NotificationCompat.Action(
                playPauseIcon, playPauseLabel, actionPi(playPauseAction, 2)))
            .addAction(NotificationCompat.Action(
                R.drawable.ic_next, "Suivant", actionPi(ACTION_NEXT, 3)))
            // ── MediaStyle ───────────────────────────────────────
            .setStyle(
                androidx.media.app.NotificationCompat.MediaStyle()
                    .setMediaSession(token)
                    .setShowActionsInCompactView(0, 1, 2)
                    .setShowCancelButton(false)
            )
            .build()
    }

    private fun buildFallbackNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Calatube")
            .setContentText("En cours…")
            .setSilent(true)
            .build()

    // ─────────────────────────────────────────────────────────────
    // Artwork
    // ─────────────────────────────────────────────────────────────
    private fun fetchBitmap(url: String): Bitmap? {
        if (url.isEmpty() || !url.startsWith("http")) return null
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = ART_CONNECT_TIMEOUT_MS
                readTimeout    = ART_READ_TIMEOUT_MS
                requestMethod  = "GET"
                setRequestProperty("User-Agent", "Calatube/2.0")
                doInput = true
            }
            try {
                if (conn.responseCode != HttpURLConnection.HTTP_OK) return null
                BitmapFactory.decodeStream(conn.inputStream)
            } finally {
                conn.disconnect()
            }
        } catch (e: IOException) {
            Log.w(TAG, "fetchBitmap failed: ${e.message}")
            null
        } catch (e: Exception) {
            Log.w(TAG, "fetchBitmap unexpected: ${e.message}")
            null
        }
    }
}
