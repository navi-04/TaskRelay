/// Application-wide constants
class AppConstants {
  // Hive Box Names
  static const String tasksBox = 'tasks_box';
  static const String settingsBox = 'settings_box';
  static const String daySummaryBox = 'day_summary_box';
  
  // Hive Type IDs
  static const int taskEntityTypeId = 0;
  static const int settingsEntityTypeId = 1;
  static const int daySummaryEntityTypeId = 2;
  
  // Default Settings
  static const int defaultDailyTimeLimitMinutes = 480; // 8 hours
  static const int defaultNotificationHour = 9;
  static const int defaultNotificationMinute = 0;
  
  // Notification IDs
  static const int dailyReminderNotificationId = 1;
  static const int carryOverAlertNotificationId = 2;
  
  // Date Format
  static const String dateFormat = 'yyyy-MM-dd';
  
  // Task Status Colors
  static const String completedColor = '#4CAF50';
  static const String partialColor = '#FFC107';
  static const String missedColor = '#F44336';
  static const String pendingColor = '#2196F3';
  
  // Animation Duration
  static const Duration animationDuration = Duration(milliseconds: 300);
}
