package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Context
import android.os.Build
import java.io.File
import java.io.FileInputStream

/** Wallpaper helpers shared by the platform channel and the background worker. */
object Wallpapers {

    /**
     * Applies [imagePath] as wallpaper for [flags] (system and/or lock screen).
     *
     * Uses [WallpaperManager.setStream] so the image is decoded by the system
     * wallpaper service instead of in this process: decoding multi-megapixel
     * photos with BitmapFactory routinely exceeded the app heap.
     */
    fun apply(context: Context, imagePath: String, flags: Int): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) return false

            val wm = WallpaperManager.getInstance(context.applicationContext)
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
