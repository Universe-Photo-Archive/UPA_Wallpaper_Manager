package eu.universe_photo_archive.upa_wallpaper_manager

import android.content.Context
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
