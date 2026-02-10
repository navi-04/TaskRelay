import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';
import 'task_type.dart';
import 'task_priority.dart';
import 'estimation_mode.dart';

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

  /// Estimation mode index: 0=time, 1=count
  @HiveField(11)
  final int estimationModeIndex;

  /// Daily weight limit (legacy, kept for Hive compat)
  @HiveField(12)
  final int dailyWeightLimit;

  /// Daily task count limit (used in count-based mode)
  @HiveField(13)
  final int dailyCountLimit;

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
    this.estimationModeIndex = 0,
    this.dailyWeightLimit = 100,
    this.dailyCountLimit = 10,
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
      estimationModeIndex: 0,
      dailyWeightLimit: 100,
      dailyCountLimit: 10,
    );
  }
  
  /// Copy with method
  /// Get estimation mode from index
  EstimationMode get estimationMode => EstimationMode.values[estimationModeIndex.clamp(0, 1)];

  /// Get the effective daily limit based on estimation mode
  int get effectiveDailyLimit {
    switch (estimationMode) {
      case EstimationMode.timeBased:
        return dailyTimeLimitMinutes;
      case EstimationMode.countBased:
        return dailyCountLimit;
    }
  }

  /// Formatted effective limit string
  String get formattedEffectiveLimit {
    switch (estimationMode) {
      case EstimationMode.timeBased:
        return formattedTimeLimit;
      case EstimationMode.countBased:
        return '$dailyCountLimit tasks';
    }
  }

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
    int? estimationModeIndex,
    int? dailyWeightLimit,
    int? dailyCountLimit,
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
      estimationModeIndex: estimationModeIndex ?? this.estimationModeIndex,
      dailyWeightLimit: dailyWeightLimit ?? this.dailyWeightLimit,
      dailyCountLimit: dailyCountLimit ?? this.dailyCountLimit,
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
        estimationModeIndex,
        dailyWeightLimit,
        dailyCountLimit,
      ];
}
