import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/task_local_datasource.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/datasources/day_summary_local_datasource.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/day_summary_repository.dart';
import '../../domain/services/notification_service.dart';
import '../../domain/services/task_carry_over_service.dart';

// ==================== DATA SOURCES ====================
// Using singleton instances to persist initialized Hive boxes across the app

final _taskLocalDataSource = TaskLocalDataSource();
final _settingsLocalDataSource = SettingsLocalDataSource();
final _daySummaryLocalDataSource = DaySummaryLocalDataSource();

final taskLocalDataSourceProvider = Provider<TaskLocalDataSource>((ref) {
  return _taskLocalDataSource;
});

final settingsLocalDataSourceProvider = Provider<SettingsLocalDataSource>((ref) {
  return _settingsLocalDataSource;
});

final daySummaryLocalDataSourceProvider = Provider<DaySummaryLocalDataSource>((ref) {
  return _daySummaryLocalDataSource;
});

// ==================== REPOSITORIES ====================

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final dataSource = ref.watch(taskLocalDataSourceProvider);
  return TaskRepository(dataSource);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final dataSource = ref.watch(settingsLocalDataSourceProvider);
  return SettingsRepository(dataSource);
});

final daySummaryRepositoryProvider = Provider<DaySummaryRepository>((ref) {
  final dataSource = ref.watch(daySummaryLocalDataSourceProvider);
  return DaySummaryRepository(dataSource);
});

// ==================== SERVICES ====================

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final taskCarryOverServiceProvider = Provider<TaskCarryOverService>((ref) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final summaryRepo = ref.watch(daySummaryRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final notificationService = ref.watch(notificationServiceProvider);
  
  return TaskCarryOverService(
    taskRepo,
    summaryRepo,
    settingsRepo,
    notificationService,
  );
});
