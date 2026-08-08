import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Release signing, read from android/key.properties.
 *
 * That file is gitignored and holds the upload keystore's passwords, so it
 * never enters the repository — see docs/RELEASE.md for how to create it.
 * Absent, the release build falls back to the debug key and SAYS SO at build
 * time: the previous arrangement signed release with the debug key silently,
 * which produces an .aab the Play Store rejects after the upload, not before.
 */
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.fcs.fcs_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (java.time backport on minSdk 24).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fcs.fcs_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Maps key comes from the GOOGLE_MAPS_API_KEY env var; falls back to a
        // placeholder so debug builds compile (the map is blank without a real key).
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            System.getenv("GOOGLE_MAPS_API_KEY") ?: "YOUR_GOOGLE_MAPS_API_KEY"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Loud, not silent. A release .aab signed with the debug key
                // uploads and is then rejected, which wastes the slowest loop
                // in the whole project — and the old comment said "for now" in
                // a file nobody opens on release day.
                logger.warn(
                    "\n*** RELEASE IS SIGNED WITH THE DEBUG KEY ***\n" +
                    "    android/key.properties is missing, so this build " +
                    "CANNOT be published.\n" +
                    "    See docs/RELEASE.md to create the upload keystore.\n"
                )
                signingConfigs.getByName("debug")
            }
            // R8 on, with the Flutter defaults. Off, the .aab is ~30% larger
            // for no benefit; on without the Flutter rules it strips code the
            // engine looks up reflectively.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
