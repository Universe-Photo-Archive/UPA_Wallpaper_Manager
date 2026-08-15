package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Intent
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {

    private val WALLPAPER_CHANNEL = "eu.universe_photo_archive/wallpaper"
    private val LOCKSCREEN_CHANNEL = "eu.universe_photo_archive/lockscreen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Wallpaper channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WALLPAPER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        result.success(applyWallpaper(imagePath, WallpaperManager.FLAG_SYSTEM))
                    }
                    "getWallpaper" -> {
                        // Android does not expose the current wallpaper's file
                        // path; the Dart side treats null as "unknown".
                        result.success(null)
                    }
                    "getScreens" -> {
                        result.success(getScreens())
                    }
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

        // Lockscreen channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCKSCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setLockscreen" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        result.success(applyWallpaper(imagePath, WallpaperManager.FLAG_LOCK))
                    }
                    "removeLockscreen" -> {
                        try {
                            val wm = WallpaperManager.getInstance(applicationContext)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                wm.clear(WallpaperManager.FLAG_LOCK)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isSupported" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                    }
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
     * photos with BitmapFactory routinely exceeded the app heap, and Android
     * killed the app mid-rotation (which both stopped the background rotation
     * and made the UI restart on the home tab).
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
}
