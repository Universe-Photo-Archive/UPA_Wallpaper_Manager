package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.Application
import android.app.WallpaperManager
import android.content.Intent
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.io.FileInputStream

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
 * theme list, rotation timers — alive across those recreations; the activity
 * simply re-attaches to the running engine.
 *
 * The platform channels also live here (bound to the application context)
 * so a rotation triggered while no activity exists still reaches native code.
 */
class MainApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        registerChannels(engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    private fun registerChannels(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, WALLPAPER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        result.success(
                            applyWallpaper(imagePath, WallpaperManager.FLAG_SYSTEM)
                        )
                    }
                    "getWallpaper" -> {
                        // Android does not expose the current wallpaper's file
                        // path; the Dart side treats null as "unknown".
                        result.success(null)
                    }
                    "getScreens" -> result.success(getScreens())
                    "startBackgroundService" -> {
                        startRotationService()
                        result.success(true)
                    }
                    "stopBackgroundService" -> {
                        stopRotationService()
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
                            applyWallpaper(imagePath, WallpaperManager.FLAG_LOCK)
                        )
                    }
                    "removeLockscreen" -> {
                        result.success(clearLockscreen())
                    }
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
     * Applies [imagePath] as wallpaper for [flags] (system and/or lock).
     *
     * Uses [WallpaperManager.setStream] so the image is decoded by the system
     * wallpaper service instead of in this process: decoding multi-megapixel
     * photos with BitmapFactory routinely exceeded the app heap.
     */
    private fun applyWallpaper(imagePath: String, flags: Int): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) return false

            val wm = WallpaperManager.getInstance(applicationContext)
            FileInputStream(file).use { stream ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    wm.setStream(stream, null, true, flags)
                } else {
                    wm.setStream(stream)
                }
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun clearLockscreen(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                WallpaperManager.getInstance(applicationContext)
                    .clear(WallpaperManager.FLAG_LOCK)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun getScreens(): List<Map<String, Any>> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)

        return listOf(
            mapOf(
                "id" to 0,
                "name" to "Main Screen",
                "width" to metrics.widthPixels,
                "height" to metrics.heightPixels,
                "left" to 0,
                "top" to 0,
                "isPrimary" to true
            )
        )
    }

    private fun startRotationService() {
        val intent = Intent(this, RotationForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopRotationService() {
        stopService(Intent(this, RotationForegroundService::class.java))
    }

    companion object {
        const val ENGINE_ID = "upa_main_engine"
        private const val WALLPAPER_CHANNEL = "eu.universe_photo_archive/wallpaper"
        private const val LOCKSCREEN_CHANNEL = "eu.universe_photo_archive/lockscreen"
    }
}
