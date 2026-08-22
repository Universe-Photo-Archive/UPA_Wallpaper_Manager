package eu.universe_photo_archive.upa_wallpaper_manager

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Thin activity on top of the cached engine owned by [MainApplication].
 *
 * Android 12+ destroys and recreates this activity on every wallpaper change,
 * so it must stay stateless: all Dart state and the platform channels live in
 * the cached engine and survive the recreation.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
    }

    /**
     * The slideshow's foreground service needs a visible notification, which
     * Android 13+ hides unless the user granted the permission.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return (context.applicationContext as? MainApplication)?.obtainEngine()
            ?: super.provideFlutterEngine(context)
    }

    /** The engine outlives this activity — never tear it down with the host. */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Plugins and channels are already registered on the cached engine in
        // MainApplication; registering them again here would duplicate them
        // on every activity recreation.
    }
}
