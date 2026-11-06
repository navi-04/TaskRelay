/// Reminder type for task alarms.
/// Stored as int in Hive (HiveField 17 on TaskEntity).
///   0 → fullAlarm (full-screen lock-screen alarm with sound)
///   1 → notification (simple push notification)
enum ReminderType {
  fullAlarm,
  notification;

  String get label {
    switch (this) {
      case ReminderType.fullAlarm:
        return 'Alarm';
      case ReminderType.notification:
        return 'Notification';
    }
  }

  /// Convert from stored int index (defaults to fullAlarm for unknown values).
  static ReminderType fromIndex(int index) {
    if (index >= 0 && index < ReminderType.values.length) {
      return ReminderType.values[index];
    }
    return ReminderType.fullAlarm;
  }
}
