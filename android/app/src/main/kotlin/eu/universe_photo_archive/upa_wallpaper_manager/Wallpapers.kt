package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import java.io.File
import java.io.FileInputStream

/** Wallpaper helpers shared by the platform channel and the background worker. */
object Wallpapers {

    /**
     * True when [imagePath] is a real, complete image.
     *
     * Handing a truncated file to the wallpaper service does not raise an
     * error, it just paints a blank background -- which looks exactly like
     * Android resetting the wallpaper to its default. Only the image header is
     * decoded here, so the check costs nothing.
     */
    fun isUsable(imagePath: String): Boolean {
        val file = File(imagePath)
        if (!file.exists() || file.length() == 0L) return false
        return try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(imagePath, options)
            options.outWidth > 0 && options.outHeight > 0
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Applies [imagePath] as wallpaper for [flags] (system and/or lock screen).
     *
     * Uses [WallpaperManager.setStream] so the image is decoded by the system
     * wallpaper service instead of in this process: decoding multi-megapixel
     * photos with BitmapFactory routinely exceeded the app heap.
     */
    fun apply(context: Context, imagePath: String, flags: Int): Boolean {
        return try {
            if (!isUsable(imagePath)) return false

            val wm = WallpaperManager.getInstance(context.applicationContext)
            FileInputStream(File(imagePath)).use { stream ->
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

    /**
     * Appends [message] to the log file the app shows in its settings, so a
     * background rotation can be diagnosed without a debugger attached.
     */
    fun log(context: Context, message: String) {
        try {
            val dir = File(context.filesDir, "logs")
            if (!dir.exists() && !dir.mkdirs()) return
            val stamp = java.text.SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US
            ).format(java.util.Date())
            File(dir, "upa_wallpaper.log")
                .appendText("[$stamp] [INFO ] WORKER | $message\n")
        } catch (e: Exception) {
            // Logging must never break the rotation.
        }
    }

    fun clearLockscreen(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                WallpaperManager.getInstance(context.applicationContext)
                    .clear(WallpaperManager.FLAG_LOCK)
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
