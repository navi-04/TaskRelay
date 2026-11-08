import java.util.Properties
import java.io.FileInputStream


plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// A Play bundle signed with the debug key is refused by Google (or uploaded under the wrong key), so a release BUNDLE refuses to
// build without key.properties. Debug builds, `flutter run` and release APKs for local testing do not need it.
gradle.taskGraph.whenReady {
    // the exact task of `flutter build appbundle`; an APK build has other tasks whose names merely contain it (bundleReleaseResources ...)
    if (allTasks.any { it.name == "bundleRelease" } && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "app/android/key.properties is missing. Copy key.properties.example to key.properties, fill in the upload keystore " +
                "passwords, and build again. A release bundle is never signed with the debug key.",
        )
    }
}


android {

    namespace = "com.naveenraj.taskrelay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.naveenraj.taskrelay"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Only define the release signing config when key.properties exists, so a fresh
    // clone (or CI) can still configure and build; it then falls back to debug signing.
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    testOptions {
        // Pure planner/log/diff classes are tested on the JVM; android.* calls (if any slip in) return defaults.
        unitTests.isReturnDefaultValues = true
    }
}



flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // Periodic + one-time background sync of the alarm feed (the only networking dependency; HTTP is HttpURLConnection).
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    // ComponentActivity + OnBackPressedDispatcher for the alarm screen (already on the classpath through Flutter; declared so it is explicit).
    implementation("androidx.activity:activity:1.9.0")

    testImplementation("junit:junit:4.13.2")
    // The android.jar stubs of org.json throw on the JVM; the real implementation is needed to parse the fixtures.
    testImplementation("org.json:json:20240303")
}
