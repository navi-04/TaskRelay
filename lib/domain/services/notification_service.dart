import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  
  bool _initialized = false;
  
  /// Initialize notification service
  Future<void> initialize() async {
    if (_initialized) return;
    
    print('🔧 Initializing TaskRelay NotificationService...');
    
    // Initialize timezone
    tz_data.initializeTimeZones();
    final local = tz.getLocation('America/New_York');
    tz.setLocalLocation(local);
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
    
    _initialized = true;
    print('  ✅ NotificationService ready!');
  }
  
  /// Create Android notification channels with sound and vibration
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) return;
    
    // Task Alarms Channel - High priority with sound and vibration
    final alarmChannel = AndroidNotificationChannel(
      'task_alarms',
      'Task Alarms',
      description: 'Alarm notifications for scheduled tasks',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      enableLights: true,
      ledColor: const Color(0xFFFF6B35),
      showBadge: true,
    );
    
    await androidPlugin.createNotificationChannel(alarmChannel);
    
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
  
  /// Request notification permissions (iOS)
  Future<bool> requestPermissions() async {
    // Request Android 13+ notification permission
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();
    }
    
    // Request iOS permissions
    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      return granted ?? false;
    }
    
    return true;
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
  /// Schedules a notification at the specified time for a task
  /// For permanent tasks, the alarm repeats daily
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
    
    // If time has passed today (or is within 30 seconds), schedule for tomorrow
    if (scheduledDate.isBefore(now) || scheduledDate.difference(now).inSeconds < 30) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
    final timeUntil = scheduledDate.difference(now);
    
    print('\n🔔 ========== SCHEDULING ALARM ==========');
    print('  📋 Task: "$taskTitle"');
    print('  🆔 Notification ID: $notificationId');
    print('  🕐 Current time: ${now.toString()}');
    print('  ⏰ Scheduled for: ${scheduledDate.toString()}');
    print('  ⏱️  Time until alarm: ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m ${timeUntil.inSeconds % 60}s');
    print('  🔁 Daily repeat: $isPermanent');
    print('  🌍 Timezone: ${tz.local.name}');
    
    final androidDetails = AndroidNotificationDetails(
      'task_alarms',
      'Task Alarms',
      channelDescription: 'Alarm notifications for scheduled tasks',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      colorized: true,
      color: const Color(0xFFFF6B35),
      timeoutAfter: 60000, // Ring for 60 seconds
      channelShowBadge: true,
      additionalFlags: Int32List.fromList([4, 128]), // FLAG_INSISTENT | FLAG_SHOW_WHEN_LOCKED
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
      sound: 'default',
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    try {
      await _notifications.zonedSchedule(
        notificationId,
        '⏰ Task Alarm',
        taskTitle,
        tzScheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: isPermanent ? DateTimeComponents.time : null,
        payload: taskId,
      );
      
      print('✅ Alarm scheduled successfully');
      
      // Verify it was scheduled
      final pendingNotifications = await _notifications.pendingNotificationRequests();
      print('📋 Pending notifications: ${pendingNotifications.length}');
      for (final notif in pendingNotifications) {
        print('  - ID: ${notif.id}, Title: ${notif.title}, Body: ${notif.body}');
      }
    } catch (e) {
      print('❌ Error scheduling alarm: $e');
      rethrow;
    }
  }
  
  /// Cancel task-specific alarm
  /// 
  /// Cancels the scheduled notification for a specific task
  Future<void> cancelTaskAlarm(String taskId) async {
    final notificationId = 1000 + taskId.hashCode.abs() % 100000;
    await _notifications.cancel(notificationId);
  }
}
