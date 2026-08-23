package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock

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
 */
object RotationAlarms {

    private const val ACTION_ROTATE = "eu.universe_photo_archive.ROTATE_TARGET"
    const val EXTRA_TARGET_ID = "targetId"

    fun schedule(context: Context, targetId: Int, delayMs: Long) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = SystemClock.elapsedRealtime() + delayMs
        try {
            manager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent(context, targetId)
            )
        } catch (e: Exception) {
            Wallpapers.log(context, "could not schedule alarm: ${e.javaClass.simpleName}")
        }
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
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue
            schedule(context, target.id, target.intervalSeconds * 1000L)
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
