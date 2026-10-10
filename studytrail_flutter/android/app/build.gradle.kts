import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing values live in android/key.properties, which is gitignored
// (root .gitignore ignores `key.properties` and `*.keystore`) — see docs/SETUP.md for
// the keytool command that creates the store. When the file is absent the
// release build falls back to the debug key, so a fresh clone can still run
// `flutter build apk --release`; it just produces an APK nobody can publish.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "in.charusat.studytrail"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Frozen at first publish, so it matches the OAuth scheme in
        // AndroidManifest.xml rather than carrying the Flutter project name.
        applicationId = "in.charusat.studytrail"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Both come from `version:` in pubspec.yaml.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            // R8 and resource shrinking are deliberately left to the Flutter
            // Gradle plugin, which turns both on for release and adds
            // flutter_proguard_rules.pro (FlutterPlugin.kt). Setting
            // `isMinifyEnabled = false` here does *not* undo it — the plugin has
            // already set `isShrinkResources = true`, and AGP then fails
            // configuration with "Removing unused resources requires unused code
            // shrinking to be turned on". Turning it off means turning off both.
            // Each plugin's keep rules arrive with its AAR, so there is nothing
            // to hand-write; `flutter build apk --release` is the path this is
            // tested on.
        }
    }
}

flutter {
    source = "../.."
}


dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
