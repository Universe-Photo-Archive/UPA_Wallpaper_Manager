package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.Application
import android.app.WallpaperManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.concurrent.TimeUnit

/**
 * Owns a long-lived [FlutterEngine] shared by every [MainActivity] instance.
 *
 * Android 12+ recreates *all* activities of an app whenever the wallpaper
 * changes (to re-derive Material You colors), and there is no way to opt out
 * via `android:configChanges`. For a wallpaper rotator that means an activity
 * teardown on every single rotation: with an activity-owned engine the Dart
 * isolate restarted each time, so the app re-ran its whole startup (offline ->
 * connecting -> loading themes -> online) and jumped back to the home tab.
 *
 * Caching the engine here keeps the Dart side — router location, providers,
 * theme list — alive across those recreations; the activity simply
 * re-attaches to the running engine.
 *
 * The platform channels also live here (bound to the application context)
 * so a rotation triggered while no activity exists still reaches native code.
 */
class MainApplication : Application() {

    /** Kept so background rotation can push updates back to the UI. */
    private var wallpaperChannel: MethodChannel? = null

    /**
     * Returns the shared engine, starting Dart on first use.
     *
     * Deliberately lazy: the background rotation also starts this process, and
     * booting the whole Dart app there would run the startup sequence —
     * network calls, downloads, cache cleanup — with no UI to show for it.
     */
    @Synchronized
    fun obtainEngine(): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }

        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        registerChannels(engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    /**
     * Tells the running app that [imagePath] is now displayed on [targetId],
     * so its preview matches the device. Ignored when no engine is running.
     */
    fun notifyWallpaperChanged(targetId: Int, imagePath: String) {
        val channel = wallpaperChannel ?: return
        Handler(Looper.getMainLooper()).post {
            runCatching {
                channel.invokeMethod(
                    "wallpaperChanged",
                    mapOf("screenId" to targetId, "path" to imagePath)
                )
            }
        }
    }

    /** Mirrors the notification's stop button into the app's own switches. */
    fun notifySlideshowStopped() {
        val channel = wallpaperChannel ?: return
        Handler(Looper.getMainLooper()).post {
            runCatching { channel.invokeMethod("slideshowStopped", null) }
        }
    }

    private fun registerChannels(engine: FlutterEngine) {
        val wallpaper = MethodChannel(engine.dartExecutor.binaryMessenger, WALLPAPER_CHANNEL)
        wallpaperChannel = wallpaper
        wallpaper.setMethodCallHandler { call, result ->
            when (call.method) {
                "setWallpaper" -> {
                    val imagePath = call.argument<String>("imagePath") ?: ""
                    // Screen 1 is the lock screen on Android; there is only
                    // ever one physical display.
                    val flag = if (call.argument<Int>("screenId") == RotationTarget.TARGET_LOCK) {
                        WallpaperManager.FLAG_LOCK
                    } else {
                        WallpaperManager.FLAG_SYSTEM
                    }
                    result.success(Wallpapers.apply(this, imagePath, flag))
                }
                "setBothWallpapers" -> {
                    val imagePath = call.argument<String>("imagePath") ?: ""
                    val home = Wallpapers.apply(this, imagePath, WallpaperManager.FLAG_SYSTEM)
                    val lock = Wallpapers.apply(this, imagePath, WallpaperManager.FLAG_LOCK)
                    result.success(home && lock)
                }
                "getWallpaper" -> {
                    // Android does not expose the current wallpaper's file
                    // path; the Dart side treats null as "unknown".
                    result.success(null)
                }
                "getScreens" -> result.success(getScreens())
                "startForegroundRotation" -> {
                    RotationForegroundService.start(this)
                    result.success(true)
                }
                "stopForegroundRotation" -> {
                    RotationForegroundService.stop(this)
                    result.success(true)
                }
                "schedulePeriodicRotation" -> {
                    val minutes = (call.argument<Int>("intervalMinutes") ?: 15)
                        .coerceAtLeast(MIN_INTERVAL_MINUTES)
                    scheduleFallback(minutes)
                    result.success(true)
                }
                "cancelPeriodicRotation" -> {
                    WorkManager.getInstance(this).cancelUniqueWork(ROTATION_WORK)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(engine.dartExecutor.binaryMessenger, LOCKSCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLockscreen" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        result.success(
                            Wallpapers.apply(this, imagePath, WallpaperManager.FLAG_LOCK)
                        )
                    }
                    "removeLockscreen" -> result.success(Wallpapers.clearLockscreen(this))
                    "isSupported" ->
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    // No elevation concept on Android — the Windows-only
                    // requirements are always satisfied here.
                    "isAdmin" -> result.success(true)
                    "isWindowsEditionSupported" ->
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    "isLockscreenSupported" ->
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Safety net for the cases where the foreground service is not alive:
     * after a reboot, or once a manufacturer's task killer has taken it down.
     * The job rotates only when the service is gone, so the two never fight.
     */
    private fun scheduleFallback(intervalMinutes: Int) {
        val request = PeriodicWorkRequestBuilder<RotationWorker>(
            intervalMinutes.toLong(), TimeUnit.MINUTES
        ).setInputData(Data.Builder().build()).build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            ROTATION_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            request
        )
    }

    private fun getScreens(): List<Map<String, Any>> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)

        // A phone has one display but two wallpaper slots. Exposing them as
        // two "screens" lets the shared rotation code drive each one with its
        // own theme and delay, exactly like two monitors on the desktop.
        return listOf(
            mapOf(
                "id" to RotationTarget.TARGET_HOME,
                "name" to getString(R.string.rotation_target_home),
                "width" to metrics.widthPixels,
                "height" to metrics.heightPixels,
                "left" to 0,
                "top" to 0,
                "isPrimary" to true
            ),
            mapOf(
                "id" to RotationTarget.TARGET_LOCK,
                "name" to getString(R.string.rotation_target_lock),
                "width" to metrics.widthPixels,
                "height" to metrics.heightPixels,
                "left" to 0,
                "top" to 0,
                "isPrimary" to false
            )
        )
    }

    companion object {
        const val ENGINE_ID = "upa_main_engine"

        /** WorkManager refuses to run a periodic job more often than this. */
        const val MIN_INTERVAL_MINUTES = 15

        private const val ROTATION_WORK = "upa_wallpaper_rotation"
        private const val WALLPAPER_CHANNEL = "eu.universe_photo_archive/wallpaper"
        private const val LOCKSCREEN_CHANNEL = "eu.universe_photo_archive/lockscreen"
    }
}
