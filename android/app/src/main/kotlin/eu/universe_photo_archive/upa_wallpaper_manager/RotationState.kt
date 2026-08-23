package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.WallpaperManager
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * The rotation settings shared between Dart and the native background code.
 *
 * Dart owns the schedule (which target rotates, how often, with which images);
 * the native side owns what is currently displayed. Both sides read-modify-
 * write the same JSON file, each touching only the fields it owns.
 *
 * Target 0 is the home-screen wallpaper, target 1 the lock screen. They rotate
 * independently, each with its own theme, delay and image pool.
 */
data class RotationTarget(
    val id: Int,
    val enabled: Boolean,
    val intervalSeconds: Long,
    val theme: String,
    val images: List<String>,
    val current: String?
) {
    val wallpaperFlag: Int
        get() = if (id == TARGET_LOCK) {
            WallpaperManager.FLAG_LOCK
        } else {
            WallpaperManager.FLAG_SYSTEM
        }

    companion object {
        const val TARGET_HOME = 0
        const val TARGET_LOCK = 1
    }
}

object RotationState {

    const val FILE_NAME = "rotation_state.json"

    fun file(context: Context): File = File(context.filesDir, FILE_NAME)

    fun read(context: Context): JSONObject? {
        val file = file(context)
        if (!file.exists()) return null
        return try {
            JSONObject(file.readText())
        } catch (e: Exception) {
            null
        }
    }

    fun isPaused(state: JSONObject): Boolean = state.optBoolean("paused", false)

    fun targets(state: JSONObject): List<RotationTarget> {
        val array = state.optJSONArray("targets") ?: return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            val obj = array.optJSONObject(index) ?: return@mapNotNull null
            val images = obj.optJSONArray("images") ?: JSONArray()
            RotationTarget(
                id = obj.optInt("id", RotationTarget.TARGET_HOME),
                enabled = obj.optBoolean("enabled", false),
                // Never trust a zero here: it would busy-loop the service.
                intervalSeconds = obj.optLong("intervalSeconds", 900L)
                    .coerceAtLeast(60L),
                theme = obj.optString("theme", ""),
                images = (0 until images.length()).mapNotNull { images.optString(it, null) },
                current = obj.optString("current", "").ifEmpty { null }
            )
        }
    }

    /** True when at least one target should be rotating right now. */
    fun hasActiveTarget(state: JSONObject): Boolean =
        !isPaused(state) && targets(state).any { it.enabled && it.images.isNotEmpty() }

    /**
     * Notification text in the language chosen inside the app.
     *
     * Android string resources follow the *device* language, which is not
     * necessarily the one the user picked in the app, so the app supplies its
     * own translations and the resources are only a fallback.
     */
    fun label(context: Context, key: String, fallbackRes: Int): String {
        val state = read(context)
        val labels = state?.optJSONObject("labels")
        val value = labels?.optString(key, "") ?: ""
        return value.ifEmpty { context.getString(fallbackRes) }
    }

    /**
     * Minutes from midnight until the quiet window ends, or null when the
     * slideshow may run right now.
     *
     * The window is evaluated against local time and may wrap past midnight.
     */
    fun minutesUntilQuietEnds(state: JSONObject): Int? {
        val quiet = state.optJSONObject("quietHours") ?: return null
        if (!quiet.optBoolean("enabled", false)) return null

        val start = quiet.optInt("startMinutes", 0)
        val end = quiet.optInt("endMinutes", 0)
        if (start == end) return null

        val now = Calendar.getInstance()
        val current = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        val inside = if (start < end) {
            current >= start && current < end
        } else {
            current >= start || current < end
        }
        if (!inside) return null

        val remaining = if (current < end) end - current else (24 * 60 - current) + end
        // Never return zero: the caller uses this as a delay.
        return remaining.coerceAtLeast(1)
    }

    @Synchronized
    fun setPaused(context: Context, paused: Boolean) {
        val state = read(context) ?: return
        state.put("paused", paused)
        write(context, state)
    }

    /**
     * Turns every slot off, as the notification's stop button does.
     *
     * Disabling the targets rather than setting a pause flag is what lets the
     * app's own switches bring the slideshow back: they drive exactly the same
     * state, so the user always sees where things stand.
     */
    @Synchronized
    fun disableAllTargets(context: Context) {
        val state = read(context) ?: return
        state.put("paused", false)
        val array = state.optJSONArray("targets") ?: return
        for (index in 0 until array.length()) {
            array.optJSONObject(index)?.put("enabled", false)
        }
        write(context, state)
    }

    @Synchronized
    fun setCurrent(context: Context, targetId: Int, path: String) {
        val state = read(context) ?: return
        val array = state.optJSONArray("targets") ?: return
        for (index in 0 until array.length()) {
            val obj = array.optJSONObject(index) ?: continue
            if (obj.optInt("id", -1) == targetId) {
                obj.put("current", path)
                // Stamped so the WorkManager fallback can tell a healthy
                // slideshow from one whose wake-ups stopped being delivered.
                obj.put("lastRotationAt", System.currentTimeMillis())
                break
            }
        }
        write(context, state)
    }

    /** Milliseconds since [targetId] last changed, or null if never. */
    fun millisSinceRotation(state: JSONObject, targetId: Int): Long? {
        val array = state.optJSONArray("targets") ?: return null
        for (index in 0 until array.length()) {
            val obj = array.optJSONObject(index) ?: continue
            if (obj.optInt("id", -1) == targetId) {
                val at = obj.optLong("lastRotationAt", 0L)
                return if (at <= 0L) null else System.currentTimeMillis() - at
            }
        }
        return null
    }

    private fun write(context: Context, state: JSONObject) {
        try {
            file(context).writeText(state.toString())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Applies the next image of [target] and returns it, or null when nothing
     * could be applied.
     *
     * Unreadable files are dropped rather than shown: handing a truncated
     * image to the wallpaper service paints a blank background instead of
     * failing, which looks like Android resetting the wallpaper.
     */
    fun rotate(context: Context, target: RotationTarget): String? {
        val available = target.images.filter { File(it).exists() }
        if (available.isEmpty()) {
            Wallpapers.log(context, "target ${target.id}: no image available")
            return null
        }

        val pool = (available.filterNot { it == target.current }
            .ifEmpty { available })
            .shuffled()

        for (candidate in pool) {
            if (!Wallpapers.isUsable(candidate)) {
                Wallpapers.log(context, "discarding unusable $candidate")
                runCatching { File(candidate).delete() }
                continue
            }
            if (Wallpapers.apply(context, candidate, target.wallpaperFlag)) {
                setCurrent(context, target.id, candidate)
                Wallpapers.log(context, "target ${target.id}: applied $candidate")
                (context.applicationContext as? MainApplication)
                    ?.notifyWallpaperChanged(target.id, candidate)
                return candidate
            }
        }

        Wallpapers.log(context, "target ${target.id}: no usable image")
        return null
    }
}
