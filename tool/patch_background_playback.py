#!/usr/bin/env python3
"""Adds background playback (foreground media service) to the Android project.

Run after `flutter create . --platforms=android` AND after
tool/patch_main_activity.py (the GitHub workflow does it):

    python3 tool/patch_background_playback.py

  * android/.../PlaybackService.kt  - foreground service with a real MEDIA
    notification (MediaSession + MediaStyle: rewind 10s, play/pause, forward
    10s, stop) shown in the tray and on the lock screen, so playback survives
    minimising the app and locking the screen
  * MainActivity.kt                 - `footbolive/playback` MethodChannel
    (start / stop) used by lib/services/background_playback.dart
  * AndroidManifest.xml             - service + FOREGROUND_SERVICE_MEDIA_PLAYBACK
    and WAKE_LOCK permissions
Safe to run more than once.
"""
import glob
import re
import sys

matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
activity = matches[0]
src = open(activity, encoding="utf8").read()
pkg = re.search(r"^package\s+([\w.]+)", src, re.M).group(1)
folder = activity.rsplit("/", 1)[0]

service = '''package __PKG__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process alive while a video plays and shows a MEDIA notification
 * (tray + lock screen) with rewind 10s / play-pause / forward 10s / stop.
 * Button taps are sent to Flutter through [onAction].
 */
class PlaybackService : Service() {
    companion object {
        const val CHANNEL = "playback_media"
        const val NOTIFICATION_ID = 4107
        const val ACTION_STOP = "__PKG__.STOP_PLAYBACK"
        const val ACTION_PLAY = "__PKG__.PLAY_PLAYBACK"
        const val ACTION_PAUSE = "__PKG__.PAUSE_PLAYBACK"
        const val ACTION_REWIND = "__PKG__.REWIND_PLAYBACK"
        const val ACTION_FORWARD = "__PKG__.FORWARD_PLAYBACK"

        /** Set by MainActivity: forwards "play", "pause", "rewind", "forward", "stop" to Flutter. */
        @Volatile
        var onAction: ((String) -> Unit)? = null

        /** The running service, so Flutter can update the play/pause state. */
        @Volatile
        var instance: PlaybackService? = null
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null
    private var session: MediaSession? = null
    private var title: String = "Streambox"
    private var playing: Boolean = true

    /** Keeps the CPU and Wi-Fi awake while the screen is off, otherwise the stream stalls. */
    private fun lock() {
        try {
            if (wake == null) {
                wake = (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "streambox:playback")
                    .apply { setReferenceCounted(false) }
            }
            if (wake?.isHeld != true) wake?.acquire(6 * 60 * 60 * 1000L)
            if (wifi == null) {
                wifi = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                    .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "streambox:playback")
                    .apply { setReferenceCounted(false) }
            }
            if (wifi?.isHeld != true) wifi?.acquire()
        } catch (e: Exception) {
        }
    }

    private fun unlock() {
        try {
            if (wake?.isHeld == true) wake?.release()
            if (wifi?.isHeld == true) wifi?.release()
        } catch (e: Exception) {
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        try {
            val s = MediaSession(this, "streambox-playback")
            @Suppress("DEPRECATION")
            s.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
            s.setCallback(object : MediaSession.Callback() {
                override fun onPlay() = act("play")
                override fun onPause() = act("pause")
                override fun onFastForward() = act("forward")
                override fun onRewind() = act("rewind")
                override fun onSkipToNext() = act("forward")
                override fun onSkipToPrevious() = act("rewind")
                override fun onStop() = act("stop")
            })
            s.isActive = true
            session = s
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        unlock()
        instance = null
        try {
            session?.isActive = false
            session?.release()
        } catch (e: Exception) {
        }
        session = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** A button was pressed (notification, lock screen or headset). */
    private fun act(name: String) {
        when (name) {
            "play" -> { playing = true; refresh() }
            "pause" -> { playing = false; refresh() }
            "stop" -> {
                onAction?.invoke("stop")
                shutDown()
                return
            }
        }
        onAction?.invoke(name)
    }

    /** Called from Flutter when the real play/pause state changes. */
    fun setPlaying(value: Boolean) {
        if (playing == value) return
        playing = value
        refresh()
    }

    private fun refresh() {
        updateSession()
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, build())
        } catch (e: Exception) {
        }
    }

    private fun updateSession() {
        val s = session ?: return
        try {
            s.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, "Streambox")
                    .build()
            )
            s.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_FAST_FORWARD or
                            PlaybackState.ACTION_REWIND or PlaybackState.ACTION_STOP
                    )
                    .setState(
                        if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1f
                    )
                    .build()
            )
        } catch (e: Exception) {
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { act("stop"); return START_NOT_STICKY }
            ACTION_PLAY -> { act("play"); return START_NOT_STICKY }
            ACTION_PAUSE -> { act("pause"); return START_NOT_STICKY }
            ACTION_REWIND -> { act("rewind"); return START_NOT_STICKY }
            ACTION_FORWARD -> { act("forward"); return START_NOT_STICKY }
        }
        title = intent?.getStringExtra("title") ?: "Streambox"
        playing = intent?.getBooleanExtra("playing", true) ?: true
        lock()
        updateSession()
        val notification = build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun action(code: Int, icon: Int, label: String, act: String): Notification.Action {
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pi = PendingIntent.getService(
            this, code,
            Intent(this, PlaybackService::class.java).setAction(act),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Action.Builder(Icon.createWithResource(this, icon), label, pi).build()
    }

    private fun build(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Playback controls", NotificationManager.IMPORTANCE_LOW)
                    .apply {
                        description = "Play, pause and seek controls while a video plays in the background"
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                        setShowBadge(false)
                    }
            )
        }
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val open = PendingIntent.getActivity(this, 0, launch, immutable or PendingIntent.FLAG_UPDATE_CURRENT)
        val icon = resources.getIdentifier("ic_stat_notify", "drawable", packageName)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val style = Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2)
        session?.let { style.setMediaSession(it.sessionToken) }
        @Suppress("DEPRECATION")
        return builder
            .setSmallIcon(if (icon != 0) icon else android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(if (playing) "Playing in background" else "Paused")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .addAction(action(10, android.R.drawable.ic_media_rew, "Back 10s", ACTION_REWIND))
            .addAction(
                if (playing) action(11, android.R.drawable.ic_media_pause, "Pause", ACTION_PAUSE)
                else action(12, android.R.drawable.ic_media_play, "Play", ACTION_PLAY)
            )
            .addAction(action(13, android.R.drawable.ic_media_ff, "Forward 10s", ACTION_FORWARD))
            .addAction(action(14, android.R.drawable.ic_menu_close_clear_cancel, "Stop", ACTION_STOP))
            .setStyle(style)
            .build()
    }

    private fun shutDown() {
        unlock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** App swiped away from recents: stop playing. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        shutDown()
        super.onTaskRemoved(rootIntent)
    }
}
'''.replace("__PKG__", pkg)
open(f"{folder}/PlaybackService.kt", "w", encoding="utf8").write(service)
print("wrote", f"{folder}/PlaybackService.kt")

# ---- MainActivity: channel ----------------------------------------------
if "setupPlayback" not in src:
    for imp in ("import android.content.Intent", "import android.os.Build"):
        if imp not in src:
            src = re.sub(r"^(package\s+[\w.]+\s*\n)", r"\1\n" + imp + "\n", src, count=1, flags=re.M)
    src = src.replace(
        "super.configureFlutterEngine(flutterEngine)",
        "super.configureFlutterEngine(flutterEngine)\n        setupPlayback(flutterEngine)", 1)
    method = '''
    private fun setupPlayback(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/playback")
        PlaybackService.onAction = { name ->
            runOnUiThread { channel.invokeMethod("action", name) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    var ok = true
                    try {
                        val i = Intent(this, PlaybackService::class.java)
                            .putExtra("title", call.argument<String>("title") ?: "Streambox")
                            .putExtra("playing", call.argument<Boolean>("playing") ?: true)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                        else startService(i)
                    } catch (e: Exception) {
                        ok = false
                    }
                    result.success(ok)
                }
                "update" -> {
                    PlaybackService.instance?.setPlaying(call.argument<Boolean>("playing") ?: true)
                    result.success(true)
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, PlaybackService::class.java))
                    } catch (e: Exception) {
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
'''
    idx = src.rstrip().rfind("}")
    src = src[:idx] + method + "}\n"
    open(activity, "w", encoding="utf8").write(src)
    print("patched", activity)

# ---- manifest -----------------------------------------------------------
mpath = "android/app/src/main/AndroidManifest.xml"
m = open(mpath, encoding="utf8").read()
add = ""
for p in ("android.permission.FOREGROUND_SERVICE",
          "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
          "android.permission.WAKE_LOCK"):
    if p not in m:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    m = m.replace("<application", add + "    <application", 1)
if "PlaybackService" not in m:
    m = m.replace(
        "</application>",
        '    <service android:name=".PlaybackService" android:exported="false" '
        'android:foregroundServiceType="mediaPlayback"/>\n    </application>', 1)
open(mpath, "w", encoding="utf8").write(m)
print("patched", mpath)
