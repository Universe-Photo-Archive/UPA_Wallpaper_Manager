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
class RotationWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val state = RotationState.read(applicationContext) ?: return Result.success()
        if (RotationState.isPaused(state)) return Result.success()

        var recovered = false
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue

            val since = RotationState.millisSinceRotation(state, target.id)
            val overdueAfter = target.intervalSeconds * 1000L * 2
            // Never rotated yet, or silent for twice its delay: something ate
            // the alarm.
            if (since != null && since < overdueAfter) continue

            Wallpapers.log(
                applicationContext,
                "watchdog: target ${target.id} overdue (${since ?: -1} ms)"
            )
            RotationState.rotate(applicationContext, target)
            RotationAlarms.schedule(
                applicationContext, target.id, target.intervalSeconds * 1000L
            )
            recovered = true
        }

        if (recovered) {
            RotationForegroundService.refreshNotification(applicationContext)
        }
        return Result.success()
    }
}
