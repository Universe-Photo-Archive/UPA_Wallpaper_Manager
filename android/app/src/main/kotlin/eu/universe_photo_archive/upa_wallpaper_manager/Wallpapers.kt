package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import java.io.File
import java.io.FileInputStream

private fun String.toUri(): Uri = Uri.parse(this)

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
    fun isUsable(context: Context, imagePath: String): Boolean {
        return try {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            if (isContentUri(imagePath)) {
                // decodeStream returns null in bounds mode, so the stream --
                // not what it decodes to -- is what says the photo is
                // readable. Testing the result rejected every user photo.
                val stream = context.contentResolver.openInputStream(imagePath.toUri())
                    ?: return false
                stream.use { BitmapFactory.decodeStream(it, null, options) }
            } else {
                val file = File(imagePath)
                if (!file.exists() || file.length() == 0L) return false
                BitmapFactory.decodeFile(imagePath, options)
            }
            options.outWidth > 0 && options.outHeight > 0
        } catch (e: Exception) {
            false
        }
    }

    /** True for the user's own photos, referenced in place rather than copied. */
    fun isContentUri(reference: String): Boolean = reference.startsWith("content://")

    /**
     * Applies [imagePath] as wallpaper for [flags] (system and/or lock screen).
     *
     * Uses [WallpaperManager.setStream] so the image is decoded by the system
     * wallpaper service instead of in this process: decoding multi-megapixel
     * photos with BitmapFactory routinely exceeded the app heap.
     *
     * A photo of the user's own is referenced as a `content://` URI. That
     * stream cannot be reset, and [WallpaperManager.setStream] re-reads it
     * internally — the second pass is empty, the call looks successful and
     * the wallpaper never changes. Copying to a real file first is what
     * makes a custom theme usable as a wallpaper.
     */
    fun apply(context: Context, imagePath: String, flags: Int): Boolean {
        return try {
            if (!isUsable(context, imagePath)) {
                log(context, "apply refused: unusable $imagePath")
                return false
            }

            val file = if (isContentUri(imagePath)) {
                materialize(context, imagePath) ?: run {
                    log(context, "apply refused: could not copy $imagePath")
                    return false
                }
            } else {
                File(imagePath)
            }

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
            log(context, "apply failed: ${e.javaClass.simpleName}: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    /** Copies a `content://` photo to a temp file [setStream] can re-read. */
    private fun materialize(context: Context, uri: String): File? {
        return try {
            val stale = System.currentTimeMillis() - 60_000L
            context.cacheDir.listFiles { _, name -> name.startsWith("wallpaper-apply-") }
                ?.filter { it.lastModified() < stale }
                ?.forEach { it.delete() }

            val dest = File.createTempFile("wallpaper-apply-", ".bin", context.cacheDir)
            context.contentResolver.openInputStream(uri.toUri())?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: run {
                dest.delete()
                return null
            }
            if (dest.length() == 0L) {
                dest.delete()
                return null
            }
            dest
        } catch (e: Exception) {
            e.printStackTrace()
            null
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
