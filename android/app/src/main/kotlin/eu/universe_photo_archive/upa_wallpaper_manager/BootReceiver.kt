package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Puts the slideshow back on its feet after the device restarts.
 *
 * A reboot clears every alarm. WorkManager restores its own jobs on its own,
 * so the watchdog kept changing wallpapers — but the service never came back,
 * leaving the rotation running without its notification until the app was
 * opened by hand.
 *
 * Android 15 forbids most foreground service types from starting at boot;
 * `specialUse`, which this app uses, is one of the few still allowed.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val appContext = context.applicationContext
        val state = RotationState.read(appContext) ?: return
        if (!RotationState.hasActiveTarget(state)) return

        RotationAlarms.rescheduleAll(appContext)
        RotationForegroundService.start(appContext)
        Wallpapers.log(appContext, "boot: slideshow restarted")
    }
}
