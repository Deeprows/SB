#!/usr/bin/env python3
"""Adds a download foreground service (progress notification) to the Android project.

Run after `flutter create . --platforms=android` AND after
tool/patch_main_activity.py (the GitHub workflow does it):

    python3 tool/patch_download_service.py

It is used by the in-app (Dart) downloader in lib/services/download_manager.dart,
the backup that downloads a file inside the app when Android's own background
downloader refuses to start:

  * android/.../DownloadService.kt - foreground service (type dataSync) that
    keeps the app alive while files download in the background and shows ONE
    progress notification (title, percent, progress bar). It also posts the
    "Download finished" / "Download failed" notification.
  * MainActivity.kt                - `footbolive/dlservice` MethodChannel
    (start / update / stop / result / saveToDownloads) used by lib/services/download_notifier.dart
  * AndroidManifest.xml            - the service + WAKE_LOCK and
    FOREGROUND_SERVICE_DATA_SYNC permissions
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
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process alive while files download inside the app and shows one
 * ongoing progress notification. Flutter updates it through [update].
 */
class DownloadService : Service() {
    companion object {
        const val CHANNEL = "download_progress"
        const val CHANNEL_DONE = "download_done"
        const val NOTIFICATION_ID = 4108

        /** The running service, so Flutter can update the notification. */
        @Volatile
        var instance: DownloadService? = null

        private fun ensureChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Download progress", NotificationManager.IMPORTANCE_LOW)
                    .apply {
                        description = "Shows how far your downloads have got"
                        setShowBadge(false)
                    }
            )
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Tells you when a download finishes or fails" }
            )
        }

        private fun smallIcon(ctx: Context, fallback: Int): Int {
            val id = ctx.resources.getIdentifier("ic_stat_notify", "drawable", ctx.packageName)
            return if (id != 0) id else fallback
        }

        private fun openApp(ctx: Context): PendingIntent? {
            val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            } ?: return null
            val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getActivity(ctx, 0, launch, immutable or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        /** A "finished" / "failed" card that stays in the tray until tapped. */
        fun showResult(ctx: Context, id: Int, title: String, text: String, ok: Boolean) {
            try {
                ensureChannels(ctx)
                val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    Notification.Builder(ctx, CHANNEL_DONE) else Notification.Builder(ctx)
                @Suppress("DEPRECATION")
                val n = builder
                    .setSmallIcon(
                        smallIcon(
                            ctx,
                            if (ok) android.R.drawable.stat_sys_download_done
                            else android.R.drawable.stat_notify_error
                        )
                    )
                    .setContentTitle(title)
                    .setContentText(text)
                    .setContentIntent(openApp(ctx))
                    .setAutoCancel(true)
                    .build()
                nm.notify(5000 + id, n)
            } catch (e: Exception) {
            }
        }
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null
    private var title: String = "Downloading"
    private var text: String = ""
    private var percent: Int = -1

    /** Keeps the CPU and Wi-Fi awake while the screen is off, otherwise the download stalls. */
    private fun lock() {
        try {
            if (wake == null) {
                wake = (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "streambox:download")
                    .apply { setReferenceCounted(false) }
            }
            if (wake?.isHeld != true) wake?.acquire(6 * 60 * 60 * 1000L)
            if (wifi == null) {
                wifi = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                    .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "streambox:download")
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
    }

    override fun onDestroy() {
        unlock()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        title = intent?.getStringExtra("title") ?: "Downloading"
        text = intent?.getStringExtra("text") ?: ""
        percent = intent?.getIntExtra("percent", -1) ?: -1
        lock()
        val notification = build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    /** Called from Flutter whenever the progress changes. */
    fun update(newTitle: String, newText: String, newPercent: Int) {
        title = newTitle
        text = newText
        percent = newPercent
        try {
            getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION_ID, build())
        } catch (e: Exception) {
        }
    }

    private fun build(): Notification {
        ensureChannels(this)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        builder
            .setSmallIcon(smallIcon(this, android.R.drawable.stat_sys_download))
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_PROGRESS)
        if (percent in 0..100) builder.setProgress(100, percent, false)
        else builder.setProgress(0, 0, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        @Suppress("DEPRECATION")
        return builder.build()
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

    /** App swiped away from recents: the downloads end with it. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        shutDown()
        super.onTaskRemoved(rootIntent)
    }
}
'''.replace("__PKG__", pkg)
open(f"{folder}/DownloadService.kt", "w", encoding="utf8").write(service)
print("wrote", f"{folder}/DownloadService.kt")

# ---- MainActivity: channel ----------------------------------------------
if "setupDownloads" not in src:
    for imp in ("import android.content.Intent", "import android.os.Build"):
        if imp not in src:
            src = re.sub(r"^(package\s+[\w.]+\s*\n)", r"\1\n" + imp + "\n", src, count=1, flags=re.M)
    src = src.replace(
        "super.configureFlutterEngine(flutterEngine)",
        "super.configureFlutterEngine(flutterEngine)\n        setupDownloads(flutterEngine)", 1)
    method = '''
    /** Copies a finished download into the phone's Downloads/DamiMovies folder. */
    private fun copyToDownloads(path: String, name: String): String? {
        val src = java.io.File(path)
        if (!src.exists()) return null
        val ext = name.substringAfterLast('.', "").lowercase()
        val mime = android.webkit.MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Download/DamiMovies")
                put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: return null
            try {
                val out = resolver.openOutputStream(uri) ?: return null
                out.use { o -> src.inputStream().use { it.copyTo(o) } }
                values.clear()
                values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try { resolver.delete(uri, null, null) } catch (x: Exception) {}
                return null
            }
        } else {
            val dir = java.io.File(
                android.os.Environment.getExternalStoragePublicDirectory(
                    android.os.Environment.DIRECTORY_DOWNLOADS
                ), "DamiMovies"
            )
            dir.mkdirs()
            src.copyTo(java.io.File(dir, name), overwrite = true)
        }
        return "Download/DamiMovies"
    }

    private fun setupDownloads(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/dlservice")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    var ok = true
                    try {
                        val i = Intent(this, DownloadService::class.java)
                            .putExtra("title", call.argument<String>("title") ?: "Downloading")
                            .putExtra("text", call.argument<String>("text") ?: "")
                            .putExtra("percent", call.argument<Int>("percent") ?: -1)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                        else startService(i)
                    } catch (e: Exception) {
                        ok = false
                    }
                    result.success(ok)
                }
                "update" -> {
                    val s = DownloadService.instance
                    if (s == null) {
                        result.success(false)
                    } else {
                        s.update(
                            call.argument<String>("title") ?: "Downloading",
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("percent") ?: -1
                        )
                        result.success(true)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, DownloadService::class.java))
                    } catch (e: Exception) {
                    }
                    result.success(true)
                }
                "saveToDownloads" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name") ?: "video.mp4"
                    if (path == null) {
                        result.success(null)
                    } else {
                        Thread {
                            val saved = try { copyToDownloads(path, name) } catch (e: Exception) { null }
                            runOnUiThread { result.success(saved) }
                        }.start()
                    }
                }
                "cookies" -> {
                    // Full cookie string the WebView holds for this address,
                    // HttpOnly cookies included (document.cookie hides those).
                    val u = call.argument<String>("url")
                    val c = try {
                        if (u == null) null else android.webkit.CookieManager.getInstance().getCookie(u)
                    } catch (e: Exception) { null }
                    result.success(c ?: "")
                }
                "result" -> {
                    DownloadService.showResult(
                        this,
                        call.argument<Int>("id") ?: 0,
                        call.argument<String>("title") ?: "Download",
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("ok") ?: true
                    )
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
          "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
          "android.permission.WAKE_LOCK",
          "android.permission.POST_NOTIFICATIONS"):
    if p not in m:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    m = m.replace("<application", add + "    <application", 1)
if "DownloadService" not in m:
    m = m.replace(
        "</application>",
        '    <service android:name=".DownloadService" android:exported="false" '
        'android:foregroundServiceType="dataSync"/>\n    </application>', 1)
open(mpath, "w", encoding="utf8").write(m)
print("patched", mpath)
