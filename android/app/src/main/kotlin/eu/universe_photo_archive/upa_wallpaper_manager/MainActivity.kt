package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.graphics.BitmapFactory
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
                        val success = setWallpaper(imagePath, WallpaperManager.FLAG_SYSTEM)
                        result.success(success)
                    }
                    "getScreens" -> {
                        result.success(getScreens())
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
                        val success = setWallpaper(imagePath, WallpaperManager.FLAG_LOCK)
                        result.success(success)
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
                    "isAdmin" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }

    private fun setWallpaper(imagePath: String, flags: Int): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) return false

            val wm = WallpaperManager.getInstance(applicationContext)
            val bitmap = BitmapFactory.decodeFile(imagePath) ?: return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                wm.setBitmap(bitmap, null, true, flags)
            } else {
                wm.setBitmap(bitmap)
            }
            bitmap.recycle()
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
}
