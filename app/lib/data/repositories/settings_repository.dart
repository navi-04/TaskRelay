import '../datasources/settings_local_datasource.dart';
import '../models/settings_entity.dart';

/// Repository for Settings operations
class SettingsRepository {
  final SettingsLocalDataSource _dataSource;
  
  SettingsRepository(this._dataSource);
  
  /// Get current settings (returns defaults if not initialized)
  SettingsEntity getSettings() {
    try {
      return _dataSource.getSettings();
    } catch (e) {
      // Return defaults if box not initialized
      return SettingsEntity.defaults();
    }
  }
  
  /// Update settings
  Future<void> updateSettings(SettingsEntity settings) async {
    try {
      await _dataSource.updateSettings(settings);
    } catch (e) {
      // Error updating settings
    }
  }
  
  /// Update daily time limit in minutes
  Future<void> updateDailyTimeLimit(int limitMinutes) async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(dailyTimeLimitMinutes: limitMinutes));
    } catch (e) {
      // Error updating daily time limit
    }
  }
  
  /// Update notification settings
  Future<void> updateNotificationSettings({
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(
        notificationsEnabled: enabled,
        notificationHour: hour,
        notificationMinute: minute,
      ));
    } catch (e) {
      // Error updating notification settings
    }
  }
  
  /// Toggle dark mode
  Future<void> toggleDarkMode() async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(isDarkMode: !current.isDarkMode));
    } catch (e) {
      // Error toggling dark mode
    }
  }
  
  /// Toggle carry over alerts
  Future<void> toggleCarryOverAlerts() async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(
        showCarryOverAlerts: !current.showCarryOverAlerts,
      ));
    } catch (e) {
      // Error toggling carry over alerts
    }
  }
  
  /// Reset to defaults
  Future<void> resetToDefaults() async {
    try {
      await _dataSource.resetSettings();
    } catch (e) {
      // Error resetting settings
    }
  }
  
  /// Watch settings changes
  Stream<SettingsEntity> watchSettings() {
    return _dataSource.watchSettings();
  }
}
