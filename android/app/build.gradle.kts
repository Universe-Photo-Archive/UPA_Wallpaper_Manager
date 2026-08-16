import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Two supported sources, in order:
//   1. android/key.properties (local builds; git-ignored, never committed)
//   2. UPA_KEYSTORE_* environment variables (CI, fed from GitHub secrets)
// When neither is available the release build falls back to the debug key so
// `flutter build apk --release` keeps working for local testing — such a build
// is NOT publishable on the Play Store.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun signingValue(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

val keystorePath = signingValue("storeFile", "UPA_KEYSTORE_PATH")
val hasReleaseKey = keystorePath != null && rootProject.file(keystorePath).exists()

android {
    namespace = "eu.universe_photo_archive.upa_wallpaper_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identity of the app on the Play Store; must match the package name
        // registered there. It intentionally differs from `namespace` above,
        // which only resolves the Kotlin classes named in the manifest.
        applicationId = "com.upa.wallpapermanager"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystorePath!!)
                storePassword = signingValue("storePassword", "UPA_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "UPA_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "UPA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "UPA: no release keystore found — signing with the debug key. " +
                        "This build cannot be uploaded to the Play Store."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Background wallpaper rotation (see RotationWorker).
    implementation("androidx.work:work-runtime-ktx:2.10.0")
}
