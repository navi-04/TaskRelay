package com.example.sampleapp

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.sampleapp/alarm"
    private val TAG = "MainActivity"
    private var methodChannel: MethodChannel? = null
    private var completeTaskReceiver: BroadcastReceiver? = null
    
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Request "Display over other apps" permission on first launch.
        // This is REQUIRED for showing the alarm overlay on OnePlus/ColorOS.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "⚠️ Overlay permission not granted — requesting")
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Cannot request overlay permission: ${e.message}", e)
            }
        } else {
            Log.d(TAG, "✅ Overlay permission granted")
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        // Register broadcast receiver for "Mark as Complete" from AlarmActivity/overlay
        registerCompleteTaskReceiver()

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleFullScreenAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    val taskTitle = call.argument<String>("taskTitle") ?: "Task Reminder"
                    val taskId = call.argument<String>("taskId") ?: ""
                    val triggerTimeMillis = call.argument<Long>("triggerTimeMillis") ?: 0L
                    val isPermanent = call.argument<Boolean>("isPermanent") ?: false
                    
                    Log.d(TAG, "🔔 Scheduling alarm from Flutter")
                    Log.d(TAG, "  - Task: $taskTitle")
                    Log.d(TAG, "  - TaskID: $taskId")
                    Log.d(TAG, "  - ID: $notificationId")
                    Log.d(TAG, "  - Time: $triggerTimeMillis")
                    Log.d(TAG, "  - Delta: ${(triggerTimeMillis - System.currentTimeMillis()) / 1000}s")
                    
                    // Log battery optimization status (informational only)
                    isBatteryOptimizationDisabled()
                    
                    // Schedule using setAlarmClock — fully immune to Doze & OEM restrictions
                    AlarmReceiver.scheduleAlarm(
                        context,
                        notificationId,
                        taskTitle,
                        triggerTimeMillis,
                        isPermanent,
                        taskId
                    )
                    
                    Log.d(TAG, "✅ Alarm scheduled successfully")
                    result.success(true)
                }
                "cancelFullScreenAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    AlarmReceiver.cancelAlarm(context, notificationId)
                    result.success(true)
                }
                "checkExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        result.success(alarmManager.canScheduleExactAlarms())
                    } else {
                        result.success(true) // Not needed on older Android
                    }
                }
                "checkSystemAlertWindowPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(context))
                    } else {
                        result.success(true)
                    }
                }
                "requestSystemAlertWindowPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                        try {
                            android.widget.Toast.makeText(context, "Please grant 'Display over other apps' for Alarm", android.widget.Toast.LENGTH_LONG).show()
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Cannot request overlay permission: ${e.message}", e)
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "checkFullScreenIntentPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        result.success(nm.canUseFullScreenIntent())
                    } else {
                        result.success(true)
                    }
                }
                "requestFullScreenIntentPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                            if (!nm.canUseFullScreenIntent()) {
                                android.widget.Toast.makeText(context, "Please allow 'Full Screen Intent' for Alarm", android.widget.Toast.LENGTH_LONG).show()
                                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                                intent.data = Uri.parse("package:$packageName")
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Cannot request full screen intent permission: ${e.message}", e)
                            // Fallback to generic settings
                            try {
                                val intent = Intent(Settings.ACTION_SETTINGS)
                                startActivity(intent)
                            } catch (_: Exception) {}
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    @SuppressLint("BatteryLife")
    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val isOptimizationDisabled = powerManager.isIgnoringBatteryOptimizations(packageName)
            Log.d(TAG, "Battery optimization status: ${if (isOptimizationDisabled) "Disabled (Good!)" else "Enabled (Bad!)"}")
            return isOptimizationDisabled
        }
        return true // No battery optimization on older Android versions
    }
    
    @SuppressLint("BatteryLife")
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                Log.w(TAG, "🔋 Opening battery optimization dialog...")
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to request battery exemption: ${e.message}")
                // Fallback: open battery optimization settings
                try {
                    val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    startActivity(intent)
                } catch (e2: Exception) {
                    Log.e(TAG, "❌ Failed to open battery settings: ${e2.message}")
                }
            }
        }
    }
}
