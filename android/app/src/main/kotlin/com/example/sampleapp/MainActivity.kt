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
        // Permission requests are now handled from Flutter with proper dialogs.
        // Do NOT auto-navigate to settings here.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w(TAG, "⚠️ Overlay permission not granted — will be requested from Flutter UI")
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
                "getPendingCompletions" -> {
                    // Read and clear pending task completions from SharedPreferences.
                    // These were persisted by AlarmActivity/overlay when user tapped
                    // "Mark as Complete" while the app process was not alive.
                    val prefs = context.getSharedPreferences("alarm_completions", Context.MODE_PRIVATE)
                    val pending = prefs.getStringSet("pending_task_ids", emptySet())?.toList() ?: emptyList()
                    prefs.edit().remove("pending_task_ids").apply()
                    Log.d(TAG, "📋 getPendingCompletions: ${pending.size} pending → $pending")
                    result.success(pending)
                }
                "getPendingDismissals" -> {
                    // Read and clear pending task dismissals from SharedPreferences.
                    // These were persisted by AlarmService when user tapped "Dismiss"
                    // while the app process was not alive.
                    val prefs = context.getSharedPreferences("alarm_dismissals", Context.MODE_PRIVATE)
                    val pending = prefs.getStringSet("dismissed_task_ids", emptySet())?.toList() ?: emptyList()
                    prefs.edit().remove("dismissed_task_ids").apply()
                    Log.d(TAG, "📋 getPendingDismissals: ${pending.size} pending → $pending")
                    result.success(pending)
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

    /**
     * Register a broadcast receiver to listen for "Mark as Complete" actions
     * from AlarmActivity or the overlay window, and forward to Flutter.
     */
    private fun registerCompleteTaskReceiver() {
        completeTaskReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val taskId = intent.getStringExtra("taskId") ?: ""
                val taskTitle = intent.getStringExtra("taskTitle") ?: ""
                Log.d(TAG, "📥 Received complete broadcast — taskId: $taskId, title: $taskTitle")
                
                if (taskId.isNotEmpty()) {
                    // Send to Flutter via MethodChannel
                    methodChannel?.invokeMethod("onTaskCompletedFromAlarm", mapOf(
                        "taskId" to taskId,
                        "taskTitle" to taskTitle
                    ))
                    Log.d(TAG, "📤 Forwarded to Flutter: onTaskCompletedFromAlarm($taskId)")
                }
            }
        }
        val filter = IntentFilter("com.example.sampleapp.ACTION_COMPLETE_TASK")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(completeTaskReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(completeTaskReceiver, filter)
        }
        Log.d(TAG, "✅ CompleteTask broadcast receiver registered")
    }

    override fun onDestroy() {
        try {
            completeTaskReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        completeTaskReceiver = null
        methodChannel = null
        super.onDestroy()
    }
}
