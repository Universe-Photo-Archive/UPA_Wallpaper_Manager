package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Applies one target's next wallpaper when its alarm fires, then arms the
 * following one.
 *
 * Doing the work here rather than inside the service means a rotation still
 * happens when the service has been killed — Android starts the process to
 * deliver the broadcast — which also covers the manufacturers that shut the
 * service down as soon as the app leaves the recents list.
 */
class RotationAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val targetId = intent.getIntExtra(RotationAlarms.EXTRA_TARGET_ID, -1)
        if (targetId < 0) return

        val appContext = context.applicationContext
        val pending = goAsync()
        Thread {
            try {
                val state = RotationState.read(appContext)
                if (state == null || RotationState.isPaused(state)) return@Thread

                val target = RotationState.targets(state)
                    .firstOrNull { it.id == targetId } ?: return@Thread
                if (!target.enabled || target.images.isEmpty()) return@Thread

                // Inside the user's quiet window: skip this turn and come back
                // when it closes, instead of ticking through the night.
                val quietLeft = RotationState.minutesUntilQuietEnds(state)
                if (quietLeft != null) {
                    Wallpapers.log(appContext, "quiet hours: $quietLeft min left")
                    RotationAlarms.schedule(
                        appContext, targetId, quietLeft * 60_000L
                    )
                    RotationForegroundService.refreshNotification(appContext)
                    return@Thread
                }

                RotationState.rotate(appContext, target)
                // Re-read the delay every time so a settings change takes
                // effect without restarting anything.
                RotationAlarms.schedule(
                    appContext, targetId, target.intervalSeconds * 1000L
                )
                RotationForegroundService.refreshNotification(appContext)
            } catch (e: Exception) {
                Wallpapers.log(appContext, "alarm rotation failed: ${e.message}")
            } finally {
                pending.finish()
            }
        }.start()
    }
}
