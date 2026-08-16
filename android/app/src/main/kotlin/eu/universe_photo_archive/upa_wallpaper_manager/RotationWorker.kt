package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.File

/**
 * Rotates the wallpaper while the app is not running.
 *
 * Android has no foreground service type that fits "change the wallpaper every
 * N minutes" -- `specialUse` requires a Play review and Google explicitly points
 * such cases at WorkManager -- so the background rotation is a periodic job
 * instead. WorkManager will not run more often than every 15 minutes and may
 * defer a run while the device is dozing; sub-15-minute delays therefore only
 * apply while the app is open, where the Dart timers drive the rotation.
 *
 * The job picks from the images the Dart side already downloaded, listed in a
 * small JSON state file, so no network access is needed when it wakes up.
 */
class RotationWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val statePath = inputData.getString(KEY_STATE_PATH) ?: return Result.success()
        val stateFile = File(statePath)
        if (!stateFile.exists()) return Result.success()

        val state = try {
            JSONObject(stateFile.readText())
        } catch (e: Exception) {
            return Result.success()
        }

        if (!state.optBoolean("enabled", false)) return Result.success()

        val current = state.optString("current", "")
        val images = state.optJSONArray("images") ?: return Result.success()
        val available = (0 until images.length())
            .mapNotNull { images.optString(it, null) }
            .filter { File(it).exists() }
        if (available.isEmpty()) {
            Wallpapers.log(applicationContext, "no image available, skipping")
            return Result.success()
        }

        // Avoid showing the same wallpaper twice in a row when possible.
        val pool = (available.filterNot { it == current }.ifEmpty { available })
            .shuffled()

        // Walk the candidates until one applies. A file can be unreadable if a
        // previous download was interrupted; applying it would blank the
        // wallpaper, so drop it instead of showing an empty background.
        var next: String? = null
        for (candidate in pool) {
            if (!Wallpapers.isUsable(candidate)) {
                Wallpapers.log(applicationContext, "discarding unusable $candidate")
                runCatching { File(candidate).delete() }
                continue
            }
            if (Wallpapers.apply(applicationContext, candidate, WallpaperManager.FLAG_SYSTEM)) {
                next = candidate
                break
            }
        }

        if (next == null) {
            Wallpapers.log(applicationContext, "no usable image among ${pool.size}")
            return Result.retry()
        }

        if (state.optBoolean("lockscreen", false)) {
            Wallpapers.apply(applicationContext, next, WallpaperManager.FLAG_LOCK)
        }
        Wallpapers.log(applicationContext, "applied $next")

        // Keep the in-app preview truthful when the app is open.
        (applicationContext as? MainApplication)?.notifyWallpaperChanged(next)

        // Remember the choice so the app can seed its preview on next launch
        // and the next run does not repeat it.
        try {
            state.put("current", next)
            stateFile.writeText(state.toString())
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return Result.success()
    }

    companion object {
        const val KEY_STATE_PATH = "statePath"
    }
}
