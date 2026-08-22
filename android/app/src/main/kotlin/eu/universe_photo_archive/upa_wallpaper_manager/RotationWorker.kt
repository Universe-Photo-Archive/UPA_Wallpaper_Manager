package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Safety net for the slideshow when [RotationForegroundService] is not alive.
 *
 * The service normally drives the rotation, but it does not survive a reboot
 * or a manufacturer's "clear all" task killer, and it cannot be started from
 * the background on recent Android versions. This periodic job fills those
 * gaps: it rotates once, at WorkManager's own pace (never more than every 15
 * minutes, and later than that while the device is dozing), until the user
 * opens the app again and the service takes over.
 *
 * It does nothing while the service is running, so the two never rotate the
 * same target at the same time.
 */
class RotationWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        if (RotationForegroundService.isRunning) return Result.success()

        val state = RotationState.read(applicationContext) ?: return Result.success()
        if (RotationState.isPaused(state)) return Result.success()

        var applied = false
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue
            if (RotationState.rotate(applicationContext, target) != null) applied = true
        }

        return if (applied) Result.success() else Result.retry()
    }
}
