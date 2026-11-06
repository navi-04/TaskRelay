import 'package:hive/hive.dart';
import '../models/settings_entity.dart';

/// Local data source for Settings operations using Hive
class SettingsLocalDataSource {
  static const String _boxName = 'settings_box';
  static const String _settingsKey = 'user_settings';
  
  Box<SettingsEntity>? _box;
  
  /// Initialize Hive box
  Future<void> init() async {
    try {
      _box = await Hive.openBox<SettingsEntity>(_boxName);
    } catch (e) {
      // If box fails to open (likely due to schema changes), delete and recreate
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<SettingsEntity>(_boxName);
    }
  }
  
  Box<SettingsEntity> get _settingsBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception('Settings box not initialized. Call init() first.');
    }
    return _box!;
  }
  
  /// Get current settings
  SettingsEntity getSettings() {
    return _settingsBox.get(_settingsKey, defaultValue: SettingsEntity.defaults()) 
        ?? SettingsEntity.defaults();
  }
  
  /// Update settings
  Future<void> updateSettings(SettingsEntity settings) async {
    await _settingsBox.put(_settingsKey, settings);
  }
  
  /// Reset settings to defaults
  Future<void> resetSettings() async {
    await _settingsBox.put(_settingsKey, SettingsEntity.defaults());
  }
  
  /// Watch settings changes
  Stream<SettingsEntity> watchSettings() {
    return _settingsBox.watch(key: _settingsKey).map(
      (_) => getSettings(),
    );
  }
}
