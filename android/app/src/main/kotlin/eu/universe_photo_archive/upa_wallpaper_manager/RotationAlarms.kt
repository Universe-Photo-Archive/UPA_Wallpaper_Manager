package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Wake-ups driving the slideshow.
 *
 * A [android.os.Handler] cannot be used here: `postDelayed` counts
 * `uptimeMillis`, which stops while the device sleeps deeply. A foreground
 * service keeps the process alive but does *not* keep the CPU awake, so a
 * fifteen-minute timer set at midnight had accumulated only a couple of
 * minutes by morning and never fired. Short delays appeared to work only
 * because the phone wakes often enough on its own to reach them.
 *
 * [AlarmManager] counts real elapsed time and wakes the device.
 * `setAndAllowWhileIdle` fires even in Doze and needs no permission — unlike
 * exact alarms, which Google restricts to alarm and calendar apps. The trade
 * off is that Doze will not deliver more than one such alarm every nine
 * minutes or so, which only rounds up the shortest delays.
 *
 * Wake-ups are aimed at wall-clock slots — every quarter of an hour for a
 * fifteen-minute delay — rather than "now plus the delay". A late delivery
 * then costs that single turn instead of pushing every following one back,
 * which is what made the rotation drift further and further off.
 */
object RotationAlarms {

    private const val ACTION_ROTATE = "eu.universe_photo_archive.ROTATE_TARGET"
    const val EXTRA_TARGET_ID = "targetId"

    /** Wakes up at the next wall-clock slot for [intervalSeconds]. */
    fun scheduleAligned(context: Context, targetId: Int, intervalSeconds: Long) {
        scheduleAt(context, targetId, nextSlot(intervalSeconds))
    }

    /** Wakes up [delayMs] from now, for one-off cases such as quiet hours. */
    fun scheduleIn(context: Context, targetId: Int, delayMs: Long) {
        scheduleAt(context, targetId, System.currentTimeMillis() + delayMs)
    }

    private fun scheduleAt(context: Context, targetId: Int, triggerAtMillis: Long) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        try {
            // RTC so the slot follows the clock the user reads, including
            // across a daylight-saving change.
            manager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent(context, targetId)
            )
        } catch (e: Exception) {
            Wallpapers.log(context, "could not schedule alarm: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Next multiple of [intervalSeconds] counted from local midnight.
     *
     * A slot less than ten seconds away is skipped: the wake-up that just
     * fired must not immediately schedule itself again.
     */
    private fun nextSlot(intervalSeconds: Long): Long {
        val interval = intervalSeconds.coerceAtLeast(60L) * 1000L
        val now = System.currentTimeMillis()

        val midnight = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        val elapsed = now - midnight
        var slot = midnight + ((elapsed / interval) + 1) * interval
        if (slot - now < 10_000L) slot += interval
        return slot
    }

    fun cancel(context: Context, targetId: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        runCatching { manager.cancel(pendingIntent(context, targetId)) }
    }

    fun cancelAll(context: Context) {
        cancel(context, RotationTarget.TARGET_HOME)
        cancel(context, RotationTarget.TARGET_LOCK)
    }

    /** Arms one alarm per enabled target, from the settings on disk. */
    fun rescheduleAll(context: Context) {
        cancelAll(context)
        val state = RotationState.read(context) ?: return
        if (RotationState.isPaused(state)) return
        // During the quiet window the first wake-up is pushed to its end.
        val quietLeft = RotationState.minutesUntilQuietEnds(state)
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue
            if (quietLeft != null) {
                scheduleIn(context, target.id, quietLeft * 60_000L)
            } else {
                scheduleAligned(context, target.id, target.intervalSeconds)
            }
        }
    }

    private fun pendingIntent(context: Context, targetId: Int): PendingIntent {
        val intent = Intent(context, RotationAlarmReceiver::class.java)
            .setAction(ACTION_ROTATE)
            .putExtra(EXTRA_TARGET_ID, targetId)
        return PendingIntent.getBroadcast(
            context,
            targetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
