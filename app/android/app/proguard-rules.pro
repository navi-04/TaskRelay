# TaskRelay R8 / ProGuard rules.
#
# The Flutter Gradle plugin enables R8 (minify + resource shrinking) for RELEASE builds and automatically
# passes this file next to proguard-android-optimize.txt and Flutter's own rules (see FlutterPlugin.kt), so these
# rules ARE applied. `flutter build apk --release` therefore writes build/app/outputs/mapping/release/mapping.txt;
# keep it per release so crash stack traces can be de-obfuscated (upload it to the store / crash tool).
#
# Native layer: BroadcastReceivers, Services and Activities are declared in the manifest (AAPT keeps those), but
# AlarmManager / PendingIntents / WorkManager instantiate and call into our code reflectively or across process
# boundaries, so keep every class and member in our package. The code base is small; the cost is negligible.
-keep class com.naveenraj.taskrelay.** { *; }

# WorkManager instantiates SyncWorker reflectively by class name. work-runtime ships a consumer rule for
# ListenableWorker subclasses; this is a harmless explicit guard.
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# Readable stack traces in release (pairs with mapping.txt).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
