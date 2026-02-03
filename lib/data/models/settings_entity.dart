import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';
import 'task_type.dart';
import 'task_priority.dart';

part 'settings_entity.g.dart';

/// Settings Entity - Stores user preferences
/// 
/// This entity manages:
/// - Daily time limit (max hours per day)
/// - Notification settings (enabled, time)
/// - Theme preferences
/// - First launch flag
@HiveType(typeId: 1)
class SettingsEntity extends Equatable {
    /// Username for profile
    @HiveField(9)
    final String username;

    /// Profile photo path (local file path or base64)
    @HiveField(10)
    final String? profilePhoto;
  /// Maximum total time allowed per day in minutes (max 1440 = 24 hours)
  @HiveField(0)
  final int dailyTimeLimitMinutes;
  
  /// Whether daily reminder notifications are enabled
  @HiveField(1)
  final bool notificationsEnabled;
  
  /// Hour for daily notification (0-23)
  @HiveField(2)
  final int notificationHour;
  
  /// Minute for daily notification (0-59)
  @HiveField(3)
  final int notificationMinute;
  
  /// Whether dark mode is enabled
  @HiveField(4)
  final bool isDarkMode;
  
  /// Whether to show carry-over alerts
  @HiveField(5)
  final bool showCarryOverAlerts;
  
  /// Whether this is the first app launch
  @HiveField(6)
  final bool isFirstLaunch;
  
  /// Default task type for new tasks
  @HiveField(7)
  final TaskType defaultTaskType;
  
  /// Default priority for new tasks
  @HiveField(8)
  final TaskPriority defaultPriority;
  
  const SettingsEntity({
    required this.dailyTimeLimitMinutes,
    required this.notificationsEnabled,
    required this.notificationHour,
    required this.notificationMinute,
    required this.isDarkMode,
    required this.showCarryOverAlerts,
    this.isFirstLaunch = true,
    this.defaultTaskType = TaskType.task,
    this.defaultPriority = TaskPriority.medium,
    this.username = '',
    this.profilePhoto,
  });
  
  /// Default settings (8 hours = 480 minutes)
  factory SettingsEntity.defaults() {
    return const SettingsEntity(
      dailyTimeLimitMinutes: 480,
      notificationsEnabled: true,
      notificationHour: 9,
      notificationMinute: 0,
      isDarkMode: false,
      showCarryOverAlerts: true,
      isFirstLaunch: true,
      defaultTaskType: TaskType.task,
      defaultPriority: TaskPriority.medium,
      username: '',
      profilePhoto: null,
    );
  }
  
  /// Copy with method
  SettingsEntity copyWith({
    int? dailyTimeLimitMinutes,
    bool? notificationsEnabled,
    int? notificationHour,
    int? notificationMinute,
    bool? isDarkMode,
    bool? showCarryOverAlerts,
    bool? isFirstLaunch,
    TaskType? defaultTaskType,
    TaskPriority? defaultPriority,
    String? username,
    String? profilePhoto,
  }) {
    return SettingsEntity(
      dailyTimeLimitMinutes: dailyTimeLimitMinutes ?? this.dailyTimeLimitMinutes,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationMinute: notificationMinute ?? this.notificationMinute,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      showCarryOverAlerts: showCarryOverAlerts ?? this.showCarryOverAlerts,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      defaultTaskType: defaultTaskType ?? this.defaultTaskType,
      defaultPriority: defaultPriority ?? this.defaultPriority,
      username: username ?? this.username,
      profilePhoto: profilePhoto ?? this.profilePhoto,
    );
  }
  
  /// Get formatted time limit string
  String get formattedTimeLimit {
    final hours = dailyTimeLimitMinutes ~/ 60;
    final minutes = dailyTimeLimitMinutes % 60;
    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${minutes}m';
    }
  }
  
  @override
  List<Object?> get props => [
        dailyTimeLimitMinutes,
        notificationsEnabled,
        notificationHour,
        notificationMinute,
        isDarkMode,
        showCarryOverAlerts,
        isFirstLaunch,
        defaultTaskType,
        defaultPriority,
        username,
        profilePhoto,
      ];
}
