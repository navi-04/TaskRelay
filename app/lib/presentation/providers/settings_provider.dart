import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/settings_entity.dart';
import '../../data/models/task_type.dart';
import '../../data/models/task_priority.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/task_carry_over_service.dart';
import 'providers.dart';

/// Settings State Notifier
class SettingsStateNotifier extends StateNotifier<SettingsEntity> {
    /// Update username
    Future<void> updateUsername(String username) async {
      final newSettings = state.copyWith(username: username);
      await _repository.updateSettings(newSettings);
      state = newSettings;
    }

    /// Update profile photo
    Future<void> updateProfilePhoto(String? photoPath) async {
      final newSettings = state.copyWith(profilePhoto: photoPath);
      await _repository.updateSettings(newSettings);
      state = newSettings;
    }
  final SettingsRepository _repository;
  final TaskCarryOverService _carryOverService;
  final NotificationService _notificationService;

  SettingsStateNotifier(
    this._repository,
    this._carryOverService,
    this._notificationService,
  ) : super(SettingsEntity.defaults());
  // Don't auto-load on construction - wait for explicit init
  
  /// Reload settings from repository
  void reloadSettings() {
    try {
      state = _repository.getSettings();
    } catch (e) {
      // Ignore errors during reload
    }
  }
  
  /// Update daily time limit in minutes
  Future<void> updateDailyTimeLimit(int limitMinutes) async {
    await _repository.updateDailyTimeLimit(limitMinutes);
    state = _repository.getSettings();
  }
  
  /// Update notification settings
  Future<void> updateNotificationSettings({
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    await _repository.updateNotificationSettings(
      enabled: enabled,
      hour: hour,
      minute: minute,
    );
    state = _repository.getSettings();
    
    // Reschedule notifications
    await _carryOverService.scheduleDailyReminder();
  }
  
  /// Toggle dark mode
  Future<void> toggleDarkMode() async {
    await _repository.toggleDarkMode();
    state = _repository.getSettings();
  }
  
  /// Toggle carry over alerts
  Future<void> toggleCarryOverAlerts() async {
    await _repository.toggleCarryOverAlerts();
    state = _repository.getSettings();
  }
  
  /// Complete onboarding - set isFirstLaunch to false
  Future<void> completeOnboarding() async {
    final newSettings = state.copyWith(isFirstLaunch: false);
    await _repository.updateSettings(newSettings);
    state = newSettings;
  }
  
  /// Reset to defaults
  Future<void> resetToDefaults() async {
    await _repository.resetToDefaults();
    state = _repository.getSettings();
  }
  
  /// Update default task type
  Future<void> updateDefaultTaskType(TaskType taskType) async {
    final newSettings = state.copyWith(defaultTaskType: taskType);
    await _repository.updateSettings(newSettings);
    state = newSettings;
  }
  
  /// Update default priority
  Future<void> updateDefaultPriority(TaskPriority priority) async {
    final newSettings = state.copyWith(defaultPriority: priority);
    await _repository.updateSettings(newSettings);
    state = newSettings;
  }

  /// Update estimation mode
  Future<void> updateEstimationMode(int modeIndex) async {
    final newSettings = state.copyWith(estimationModeIndex: modeIndex);
    await _repository.updateSettings(newSettings);
    state = newSettings;
  }

  /// Update daily count limit
  Future<void> updateDailyCountLimit(int limit) async {
    final newSettings = state.copyWith(dailyCountLimit: limit);
    await _repository.updateSettings(newSettings);
    state = newSettings;
  }

  /// Update end-of-day notification settings and reschedule (or cancel).
  Future<void> updateEndOfDayNotification({
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    final newSettings = state.copyWith(
      endOfDayNotificationEnabled: enabled,
      endOfDayHour: hour,
      endOfDayMinute: minute,
    );
    await _repository.updateSettings(newSettings);
    state = newSettings;

    if (newSettings.endOfDayNotificationEnabled) {
      await _notificationService.scheduleEndOfDayReminder(
        hour: newSettings.endOfDayHour,
        minute: newSettings.endOfDayMinute,
        completedCount: 0,
        totalCount: 0,
      );
    } else {
      await _notificationService.cancelEndOfDayReminder();
    }
  }
}

/// Settings State Provider
final settingsProvider = StateNotifierProvider<SettingsStateNotifier, SettingsEntity>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  final carryOverService = ref.watch(taskCarryOverServiceProvider);
  final notificationService = ref.watch(notificationServiceProvider);

  return SettingsStateNotifier(repository, carryOverService, notificationService);
});
