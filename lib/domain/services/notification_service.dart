import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Notification Service for handling local notifications
/// 
/// Manages:
/// - Daily reminder notifications
/// - Carry-over alert notifications
/// - Notification scheduling and cancellation
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  // Method channel for full-screen alarms
  static const platform = MethodChannel('com.example.sampleapp/alarm');
  
  bool _initialized = false;

  /// Callback invoked when user taps "Mark as Complete" from the alarm UI.
  /// Set this from your provider/controller to handle task completion.
  void Function(String taskId, String taskTitle)? onTaskCompletedFromAlarm;

  /// Retrieve task IDs that were marked complete from the native alarm UI
  /// while the Flutter engine was not running. The native side persists these
  /// to SharedPreferences so they survive process death.
  Future<List<String>> getPendingCompletions() async {
    try {
      final result = await platform.invokeMethod<List<dynamic>>('getPendingCompletions');
      final ids = result?.cast<String>() ?? [];
      if (ids.isNotEmpty) {
        print('📋 Found ${ids.length} pending completions from alarm: $ids');
      }
      return ids;
    } catch (e) {
      print('⚠️ getPendingCompletions failed: $e');
      return [];
    }
  }
  
  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;
    
    print('🔧 Initializing TaskRelay NotificationService...');
    
    // Initialize timezone
    tz_data.initializeTimeZones();
    // Detect the device's local timezone instead of hardcoding
    try {
      final local = tz.getLocation(DateTime.now().timeZoneName);
      tz.setLocalLocation(local);
    } catch (_) {
      // If device timezone name isn't found in the database, use UTC as fallback
      tz.setLocalLocation(tz.UTC);
    }
    print('  ✅ Timezone: ${tz.local.name}');
    
    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    // Combined initialization settings
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    // Initialize plugin
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // Create notification channels for Android with proper sound/vibration
    await _createNotificationChannels();
    
    // Listen for "Mark as Complete" from native alarm UI
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onTaskCompletedFromAlarm') {
        final taskId = call.arguments['taskId'] as String? ?? '';
        final taskTitle = call.arguments['taskTitle'] as String? ?? '';
        print('✅ Received onTaskCompletedFromAlarm: taskId=$taskId title=$taskTitle');
        onTaskCompletedFromAlarm?.call(taskId, taskTitle);
      }
    });

    _initialized = true;
    print('  ✅ NotificationService ready!');
  }
  
  /// Create Android notification channels with sound and vibration
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) return;
    
    // Task Alarms Channel - Maximum priority with alarm sound
    // Using channel ID v5 — MUST match AlarmService.ALARM_CHANNEL_ID on native side.
    // Using a fresh channel ID avoids Android caching a lower importance from old installs.
    //
    // NOTE: This channel is also created natively in AlarmService.kt.
    // Creating it from Flutter ensures it exists before any alarm is scheduled.
    final alarmChannel = AndroidNotificationChannel(
      'alarm_critical_v5',
      'Critical Alarm Alerts',
      description: 'Full-screen alarm notifications that show over lock screen',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      ledColor: const Color(0xFFFF6B35),
      showBadge: true,
    );

    await androidPlugin.createNotificationChannel(alarmChannel);

    // Delete old alarm channels to avoid confusion
    try {
      await androidPlugin.deleteNotificationChannel('task_alarms_v3');
    } catch (_) {}
    try {
      await androidPlugin.deleteNotificationChannel('alarm_trigger_v3');
    } catch (_) {}
    try {
      await androidPlugin.deleteNotificationChannel('alarm_trigger_v4');
    } catch (_) {}
    
    // Daily Reminder Channel
    const reminderChannel = AndroidNotificationChannel(
      'daily_reminder',
      'Daily Reminder',
      description: 'Daily task reminder notifications',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    
    await androidPlugin.createNotificationChannel(reminderChannel);
    
    // Carry Over Alert Channel
    const carryOverChannel = AndroidNotificationChannel(
      'carry_over_alert',
      'Carry Over Alerts',
      description: 'Alerts for carried over tasks',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    
    await androidPlugin.createNotificationChannel(carryOverChannel);
    
    // Task Reminder Channel
    const taskReminderChannel = AndroidNotificationChannel(
      'task_reminder',
      'Task Reminders',
      description: 'Task reminder notifications',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    
    await androidPlugin.createNotificationChannel(taskReminderChannel);
  }
  
  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - can navigate to specific screen
    // This can be extended with navigation logic
    print('Notification tapped: ${response.payload}');
  }
  
  /// Request basic notification & exact alarm permissions (silent — no dialog).
  /// Called during app init. Overlay & FSI are handled separately via dialogs.
  Future<bool> requestPermissions() async {
    // Request Android 13+ notification permission & exact alarms
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }

    // iOS permissions are handled by the local notifications plugin
    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosPlugin != null) {
      await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
    }
    
    return true;
  }

  // ─── Permission checks (no navigation) ────────────────────────────

  /// Check if "Display over other apps" is granted.
  Future<bool> hasOverlayPermission() async {
    try {
      return await platform.invokeMethod<bool>('checkSystemAlertWindowPermission') ?? false;
    } catch (_) {
      return true; // Assume OK on non-Android
    }
  }

  /// Check if full-screen intent is granted (Android 14+).
  Future<bool> hasFullScreenIntentPermission() async {
    try {
      return await platform.invokeMethod<bool>('checkFullScreenIntentPermission') ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Navigate to the system overlay permission settings page.
  Future<void> openOverlayPermissionSettings() async {
    try {
      await platform.invokeMethod('requestSystemAlertWindowPermission');
    } catch (e) {
      print('❌ openOverlayPermissionSettings: $e');
    }
  }

  /// Navigate to the system full-screen intent settings page.
  Future<void> openFullScreenIntentSettings() async {
    try {
      await platform.invokeMethod('requestFullScreenIntentPermission');
    } catch (e) {
      print('❌ openFullScreenIntentSettings: $e');
    }
  }

  /// **Show a dialog and request all alarm-related permissions.**
  ///
  /// Call this before scheduling any alarm, or at app launch.
  /// Shows user-friendly dialog explaining WHY each permission is needed,
  /// then navigates to system settings only after the user taps "Open Settings".
  ///
  /// Returns `true` if all required permissions are granted.
  Future<bool> ensureAlarmPermissions(BuildContext context) async {
    bool allGranted = true;

    // 1. Notification permission (Android 13+)
    final notifOk = await areNotificationsEnabled();
    if (!notifOk) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission() ?? false;
        if (!granted) allGranted = false;
      }
    }

    // 2. "Display over other apps" — show dialog first
    final overlayOk = await hasOverlayPermission();
    if (!overlayOk) {
      final userAccepted = await _showPermissionDialog(
        context,
        title: 'Display Over Other Apps',
        message:
            'TaskRelay needs the "Display over other apps" permission to show '
            'alarm notifications on your lock screen.\n\n'
            'Without this, alarms may not appear when your phone is locked.',
        buttonText: 'Open Settings',
      );
      if (userAccepted) {
        await openOverlayPermissionSettings();
      }
      // Re-check after user returns (we can't know for sure, so mark not-granted)
      allGranted = false;
    }

    // 3. Full-screen intent (Android 14+) — show dialog first
    final fsiOk = await hasFullScreenIntentPermission();
    if (!fsiOk) {
      final userAccepted = await _showPermissionDialog(
        context,
        title: 'Full-Screen Alarm',
        message:
            'TaskRelay needs the "Full-screen notifications" permission to '
            'display alarms that wake your screen.\n\n'
            'Without this, alarms may only show as a small notification.',
        buttonText: 'Open Settings',
      );
      if (userAccepted) {
        await openFullScreenIntentSettings();
      }
      allGranted = false;
    }

    return allGranted;
  }

  /// Generic permission explanation dialog.
  /// Returns `true` if user tapped [buttonText], `false` if dismissed.
  Future<bool> _showPermissionDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String buttonText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.security, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Not Now', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(buttonText),
          ),
        ],
      ),
    );
    return result ?? false;
  }
  
  /// Schedule daily reminder notification
  /// 
  /// Scheduled at user-specified time every day
  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required int pendingTasksCount,
    required int totalMinutes,
    required int carriedOverCount,
  }) async {
    await cancelDailyReminder(); // Cancel existing first
    
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
    
    // If time has passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
    
    // Format time display
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    String timeStr;
    if (hours > 0 && mins > 0) {
      timeStr = '${hours}h ${mins}m';
    } else if (hours > 0) {
      timeStr = '${hours}h';
    } else {
      timeStr = '${mins}m';
    }
    
    String title = 'Daily Task Reminder';
    String body = 'You have $pendingTasksCount tasks ($timeStr) pending today.';
    
    if (carriedOverCount > 0) {
      body += '\n$carriedOverCount tasks carried over from previous days.';
    }
    
    const androidDetails = AndroidNotificationDetails(
      'daily_reminder',
      'Daily Reminder',
      channelDescription: 'Daily task reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.zonedSchedule(
      1, // Daily reminder ID
      title,
      body,
      tzScheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
    );
  }
  
  /// Cancel daily reminder
  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(1);
  }
  
  /// Show immediate carry-over alert
  /// 
  /// Shows when tasks are carried over (non-scheduled, immediate)
  Future<void> showCarryOverAlert({
    required int carriedCount,
    required int totalMinutes,
  }) async {
    // Format time display
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    String timeStr;
    if (hours > 0 && mins > 0) {
      timeStr = '${hours}h ${mins}m';
    } else if (hours > 0) {
      timeStr = '${hours}h';
    } else {
      timeStr = '${mins}m';
    }
    
    const androidDetails = AndroidNotificationDetails(
      'carry_over_alert',
      'Carry Over Alerts',
      channelDescription: 'Alerts for carried over tasks',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      2, // Carry-over alert ID
      'Tasks Carried Over',
      '$carriedCount incomplete tasks ($timeStr) have been carried over to today.',
      details,
    );
  }
  
  /// Show immediate notification for task reminder
  Future<void> showTaskReminder({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'task_reminder',
      'Task Reminders',
      channelDescription: 'Task reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      3, // Task reminder ID
      title,
      body,
      details,
    );
  }
  
  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
  
  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
  
  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (_notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>() !=
        null) {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          false;
    }
    return true; // iOS doesn't have this check
  }
  
  /// Schedule task-specific alarm notification
  /// 
  /// Schedules a FULL-SCREEN alarm at the specified time for a task
  /// For permanent tasks, the alarm repeats daily
  /// This alarm will show over the lock screen and wake the device
  Future<void> scheduleTaskAlarm({
    required String taskId,
    required String taskTitle,
    required DateTime alarmTime,
    bool isPermanent = false,
  }) async {
    // Cancel existing alarm for this task first
    await cancelTaskAlarm(taskId);
    
    // Use task ID hash as notification ID (offset by 1000 to avoid conflicts with system notifications)
    final notificationId = 1000 + taskId.hashCode.abs() % 100000;
    
    final now = DateTime.now();
    
    // Ensure we're scheduling with today's/tomorrow's date + alarm time
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      alarmTime.hour, 
      alarmTime.minute,
      0,
      0,
    );
    
    // If time has already passed, schedule for tomorrow
    // Otherwise, schedule for today
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    final timeUntil = scheduledDate.difference(now);
    
    print('\n🔔 ========== SCHEDULING FULL-SCREEN ALARM ==========');
    print('  📋 Task: "$taskTitle"');
    print('  🆔 Notification ID: $notificationId');
    print('  🕐 Current time: ${now.toString()}');
    print('  ⏰ Scheduled for: ${scheduledDate.toString()}');
    print('  ⏱️  Time until alarm: ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m ${timeUntil.inSeconds % 60}s');
    print('  🔁 Daily repeat: $isPermanent');
    print('  📱 Full-screen: YES (works over lock screen)');
    
    try {
      // Use native Android alarm with full-screen intent
      await platform.invokeMethod('scheduleFullScreenAlarm', {
        'notificationId': notificationId,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'triggerTimeMillis': scheduledDate.millisecondsSinceEpoch,
        'isPermanent': isPermanent,
      });
      
      print('✅ Full-screen alarm scheduled successfully');
    } catch (e) {
      print('❌ Error scheduling full-screen alarm: $e');
      rethrow;
    }
  }
  
  /// Cancel task-specific alarm
  /// 
  /// Cancels the scheduled full-screen alarm for a specific task
  Future<void> cancelTaskAlarm(String taskId) async {
    final notificationId = 1000 + taskId.hashCode.abs() % 100000;
    
    try {
      await platform.invokeMethod('cancelFullScreenAlarm', {
        'notificationId': notificationId,
      });
    } catch (e) {
      print('❌ Error canceling alarm: $e');
    }
    await _notifications.cancel(notificationId);
  }

  /// Schedule a simple notification reminder for a task (no full-screen alarm).
  ///
  /// Uses flutter_local_notifications zonedSchedule on the 'task_reminder' channel.
  Future<void> scheduleTaskNotification({
    required String taskId,
    required String taskTitle,
    required DateTime alarmTime,
    bool isPermanent = false,
  }) async {
    // Cancel existing notification/alarm for this task first
    await cancelTaskAlarm(taskId);

    final notificationId = 1000 + taskId.hashCode.abs() % 100000;

    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      alarmTime.hour,
      alarmTime.minute,
      0,
      0,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    print('\n🔔 ========== SCHEDULING SIMPLE NOTIFICATION ==========');
    print('  📋 Task: "$taskTitle"');
    print('  🆔 Notification ID: $notificationId');
    print('  ⏰ Scheduled for: ${scheduledDate.toString()}');
    print('  🔁 Daily repeat: $isPermanent');
    print('  📱 Full-screen: NO (simple notification)');

    const androidDetails = AndroidNotificationDetails(
      'task_reminder',
      'Task Reminders',
      channelDescription: 'Task reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      'Task Reminder',
      taskTitle,
      tzScheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: isPermanent ? DateTimeComponents.time : null,
    );

    print('✅ Simple notification scheduled successfully');
  }
}
