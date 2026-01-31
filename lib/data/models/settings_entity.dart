import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';
import 'task_type.dart';
import 'task_priority.dart';

part 'settings_entity.g.dart';

/// Settings Entity - Stores user preferences
/// 
/// This entity manages:
/// - Daily task weight limit
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
  /// Maximum total weight allowed per day
  @HiveField(0)
  final int dailyWeightLimit;
  
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
    required this.dailyWeightLimit,
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
  
  /// Default settings
  factory SettingsEntity.defaults() {
    return const SettingsEntity(
      dailyWeightLimit: 10,
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
    int? dailyWeightLimit,
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
      dailyWeightLimit: dailyWeightLimit ?? this.dailyWeightLimit,
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
  
  @override
  List<Object?> get props => [
        dailyWeightLimit,
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
