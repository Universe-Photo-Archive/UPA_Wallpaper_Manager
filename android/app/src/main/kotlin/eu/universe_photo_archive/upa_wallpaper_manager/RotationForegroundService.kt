package eu.universe_photo_archive.upa_wallpaper_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder

/**
 * Runs the wallpaper slideshow while the app is closed.
 *
 * A deferrable WorkManager job proved unusable for this: Doze pushes it far
 * past the delay the user picked, and the aggressive task killers of several
 * manufacturers cancel scheduled work outright once the app is swiped away.
 * A foreground service is exempt from both, at the cost of the persistent
 * notification -- which doubles as the slideshow's remote control.
 *
 * The service is only alive while the user has a slideshow enabled; disabling
 * every target stops it and removes the notification. Rotation happens
 * natively, from the images Dart has already downloaded, so nothing depends on
 * the Flutter engine still being around.
 */
class RotationForegroundService : Service() {

    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private val scheduled = mutableMapOf<Int, Runnable>()

    override fun onCreate() {
        super.onCreate()
        worker = HandlerThread("upa-rotation").apply { start() }
        handler = Handler(worker.looper)
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()

        when (intent?.action) {
            ACTION_PAUSE -> RotationState.setPaused(this, true)
            ACTION_RESUME -> RotationState.setPaused(this, false)
            ACTION_NEXT -> handler.post { rotateAllNow() }
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }

        if (intent?.action == ACTION_PAUSE || intent?.action == ACTION_RESUME) {
            (applicationContext as? MainApplication)
                ?.notifyPausedChanged(intent.action == ACTION_PAUSE)
        }

        reschedule()
        updateNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        cancelAll()
        worker.quitSafely()
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --- Scheduling -------------------------------------------------------

    private fun cancelAll() {
        scheduled.values.forEach { handler.removeCallbacks(it) }
        scheduled.clear()
    }

    /** Rebuilds the per-target timers from the state file. */
    private fun reschedule() {
        cancelAll()
        val state = RotationState.read(this) ?: return
        if (RotationState.isPaused(state)) return

        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue
            scheduleNext(target.id, target.intervalSeconds * 1000L)
        }
    }

    private fun scheduleNext(targetId: Int, delayMs: Long) {
        scheduled.remove(targetId)?.let { handler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                val state = RotationState.read(this@RotationForegroundService)
                if (state == null || RotationState.isPaused(state)) return
                val target = RotationState.targets(state)
                    .firstOrNull { it.id == targetId } ?: return
                if (!target.enabled) return

                RotationState.rotate(this@RotationForegroundService, target)
                updateNotification()
                // Re-read the interval each time so a settings change applies
                // without restarting the service.
                scheduleNext(targetId, target.intervalSeconds * 1000L)
            }
        }
        scheduled[targetId] = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun rotateAllNow() {
        val state = RotationState.read(this) ?: return
        for (target in RotationState.targets(state)) {
            if (!target.enabled || target.images.isEmpty()) continue
            RotationState.rotate(this, target)
        }
        reschedule()
        updateNotification()
    }

    // --- Notification -----------------------------------------------------

    private fun startInForeground() {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.rotation_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.rotation_channel_description)
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val state = RotationState.read(this)
        val paused = state != null && RotationState.isPaused(state)
        val targets = state?.let { RotationState.targets(it) } ?: emptyList()

        val summary = when {
            paused -> getString(R.string.rotation_paused)
            targets.none { it.enabled } -> getString(R.string.rotation_idle)
            else -> targets.filter { it.enabled }.joinToString(" • ") { target ->
                val label = if (target.id == RotationTarget.TARGET_LOCK) {
                    getString(R.string.rotation_target_lock)
                } else {
                    getString(R.string.rotation_target_home)
                }
                val theme = target.theme.ifEmpty { getString(R.string.rotation_all_themes) }
                "$label : $theme"
            }
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(summary)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                if (paused) {
                    action(R.string.rotation_resume, ACTION_RESUME, 1)
                } else {
                    action(R.string.rotation_pause, ACTION_PAUSE, 2)
                }
            )
            .addAction(action(R.string.rotation_next, ACTION_NEXT, 3))
            .build()
    }

    private fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        return PendingIntent.getActivity(
            this, 0, launch, PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun action(labelRes: Int, action: String, requestCode: Int): Notification.Action {
        val intent = Intent(this, RotationForegroundService::class.java).setAction(action)
        val pending = PendingIntent.getService(
            this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE
        )
        @Suppress("DEPRECATION")
        return Notification.Action.Builder(0, getString(labelRes), pending).build()
    }

    companion object {
        /**
         * Whether the service is alive in this process. The WorkManager
         * fallback checks it so the two never rotate at the same time; when
         * the process has been killed the flag is false again, which is
         * exactly when the fallback should take over.
         */
        @Volatile
        var isRunning: Boolean = false
            private set

        const val ACTION_PAUSE = "eu.universe_photo_archive.ROTATION_PAUSE"
        const val ACTION_RESUME = "eu.universe_photo_archive.ROTATION_RESUME"
        const val ACTION_NEXT = "eu.universe_photo_archive.ROTATION_NEXT"
        const val ACTION_STOP = "eu.universe_photo_archive.ROTATION_STOP"

        private const val CHANNEL_ID = "upa_rotation"
        private const val NOTIFICATION_ID = 42

        /**
         * Starts the service, or hands fresh settings to the running one.
         *
         * Android 12+ forbids *starting* a foreground service from the
         * background, so an already-running service is updated with a plain
         * [Context.startService] instead. The refusal is caught rather than
         * fatal: the settings file is written either way, and the service
         * picks them up on its next tick or when the app is next opened.
         */
        fun start(context: Context) {
            val intent = Intent(context, RotationForegroundService::class.java)
            try {
                if (isRunning || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    context.startService(intent)
                } else {
                    context.startForegroundService(intent)
                }
            } catch (e: Exception) {
                Wallpapers.log(context, "could not start service: ${e.javaClass.simpleName}")
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.stopService(Intent(context, RotationForegroundService::class.java))
            }
        }
    }
}
