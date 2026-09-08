import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives outside the repo: android/key.properties (gitignored)
// points at the keystore and carries its passwords. Without it the release
// build falls back to the debug key so a fresh clone still builds.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.erichuanp.anime_now"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.erichuanp.animenow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Version = release date: pubspec `version: YYYY.M.D+N` shows as YYYY.M.D.N
        // (N counts releases on the same day) and versionCode = YYYYMMDDNN.
        // Read straight from pubspec.yaml because Flutter turns a build number
        // of 0 into 1. With split APKs Flutter adds 1000 * ABI_VERSION on top.
        val pubspecVersion = File(rootProject.projectDir, "../pubspec.yaml").readLines()
            .first { it.startsWith("version:") }.substringAfter("version:").trim()
        val datePart = pubspecVersion.substringBefore("+")
        val sameDay = pubspecVersion.substringAfter("+", "0").toInt()
        val date = datePart.split(".").map { it.toInt() }
        versionName = "$datePart.$sameDay"
        versionCode = date[0] * 1000000 + date[1] * 10000 + date[2] * 100 + sameDay
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
