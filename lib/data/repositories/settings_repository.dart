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
      print('Error updating settings: $e');
    }
  }
  
  /// Update daily time limit in minutes
  Future<void> updateDailyTimeLimit(int limitMinutes) async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(dailyTimeLimitMinutes: limitMinutes));
    } catch (e) {
      print('Error updating daily time limit: $e');
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
      print('Error updating notification settings: $e');
    }
  }
  
  /// Toggle dark mode
  Future<void> toggleDarkMode() async {
    try {
      final current = _dataSource.getSettings();
      await _dataSource.updateSettings(current.copyWith(isDarkMode: !current.isDarkMode));
    } catch (e) {
      print('Error toggling dark mode: $e');
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
      print('Error toggling carry over alerts: $e');
    }
  }
  
  /// Reset to defaults
  Future<void> resetToDefaults() async {
    try {
      await _dataSource.resetSettings();
    } catch (e) {
      print('Error resetting settings: $e');
    }
  }
  
  /// Watch settings changes
  Stream<SettingsEntity> watchSettings() {
    return _dataSource.watchSettings();
  }
}
