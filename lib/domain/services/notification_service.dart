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
    
    // Initialize timezone
    tz_data.initializeTimeZones();
    
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
    
    _initialized = true;
  }
  
  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - can navigate to specific screen
    // This can be extended with navigation logic
    print('Notification tapped: ${response.payload}');
  }
  
  /// Request notification permissions (iOS)
  Future<bool> requestPermissions() async {
    final plugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (plugin != null) {
      final granted = await plugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    
    // Android doesn't require runtime permission request for notifications
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
}
