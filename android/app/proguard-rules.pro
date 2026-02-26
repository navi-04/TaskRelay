# ─── TaskRelay Alarm System ───────────────────────────────────────────────────
# Keep ALL alarm-related classes intact — R8 must not obfuscate or remove
# any members, because they are invoked across class boundaries, via
# PendingIntents, method channels, and BroadcastReceivers that R8 cannot
# fully trace.

-keep class com.naveenraj.taskrelay.AlarmReceiver { *; }
-keep class com.naveenraj.taskrelay.AlarmReceiver$Companion { *; }

-keep class com.naveenraj.taskrelay.AlarmService { *; }
-keep class com.naveenraj.taskrelay.AlarmService$Companion { *; }

-keep class com.naveenraj.taskrelay.AlarmActivity { *; }
-keep class com.naveenraj.taskrelay.AlarmActivity$Companion { *; }

-keep class com.naveenraj.taskrelay.MainActivity { *; }

# ─── Flutter Local Notifications Plugin ───────────────────────────────────────
# The plugin's receivers are declared in AndroidManifest.xml but R8 may still
# strip internal helpers. Keep the whole package to be safe.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ─── Android & AndroidX components used by alarm infrastructure ──────────────
-keep class androidx.core.app.NotificationCompat { *; }
-keep class androidx.core.app.NotificationCompat$Builder { *; }
-keep class androidx.core.app.NotificationCompat$BigTextStyle { *; }

# ─── Prevent R8 from stripping Kotlin companion objects & metadata ────────────
-keepclassmembers class * {
    static ** Companion;
}

# ─── Keep enum classes used in alarm/notification system ──────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
