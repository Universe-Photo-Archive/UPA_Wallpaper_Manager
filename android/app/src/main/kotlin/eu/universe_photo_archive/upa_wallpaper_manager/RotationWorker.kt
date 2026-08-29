package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Watchdog for the slideshow.
 *
 * The rotation normally runs on alarms armed by [RotationAlarms]. Those can
 * still be lost: a reboot clears them, and a few manufacturers drop an app's
 * alarms along with its process. This periodic job notices a target that is
 * long overdue, rotates it once and re-arms its alarm.
 *
 * It deliberately does not check whether the service is alive — the bug this
 * guards against is exactly a live service whose wake-ups never arrive. It
 * keys off the last rotation instead, so a healthy slideshow is left alone.
 */
private const val THIRTY_MINUTES = 30 * 60 * 1000L

class RotationWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val state = RotationState.read(applicationContext) ?: return Result.success()
        if (RotationState.isPaused(state)) return Result.success()

        // The quiet window legitimately leaves every slot silent for hours,
        // which used to look like a stall: the watchdog then "repaired" the
        // slideshow all night long, changing wallpapers the user had asked to
        // leave alone.
        if (RotationState.minutesUntilQuietEnds(state) != null) {
            return Result.success()
        }

        var recovered = false
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue

            val since = RotationState.millisSinceRotation(state, target.id)
            // Unknown means the settings were just written and no wake-up has
            // landed yet — the alarms are in charge, so stay out of the way.
            if (since == null) continue

            // Doze throttles wake-ups to roughly one every nine minutes, so a
            // short delay legitimately runs late. The floor keeps this a
            // safety net instead of a second rotator racing the alarms.
            val overdueAfter =
                maxOf(target.intervalSeconds * 1000L * 2, THIRTY_MINUTES)
            if (since < overdueAfter) continue

            Wallpapers.log(
                applicationContext,
                "watchdog: target ${target.id} silent for ${since / 1000}s"
            )
            RotationState.rotate(applicationContext, target)
            RotationAlarms.scheduleAligned(
                applicationContext, target.id, target.intervalSeconds
            )
            recovered = true
        }

        if (recovered) {
            RotationForegroundService.refreshNotification(applicationContext)
        }
        return Result.success()
    }
}
