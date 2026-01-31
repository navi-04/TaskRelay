import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/custom_task_type.dart';
import '../../data/datasources/custom_type_local_datasource.dart';

/// Singleton instance for custom type data source
final _customTypeDataSource = CustomTypeLocalDataSource();

/// Provider for custom type data source
final customTypeLocalDataSourceProvider = Provider<CustomTypeLocalDataSource>((ref) {
  return _customTypeDataSource;
});

/// State for custom types
class CustomTypesState {
  final List<CustomTaskType> taskTypes;
  final List<CustomPriority> priorities;
  final bool isLoading;
  final String? error;
  
  CustomTypesState({
    required this.taskTypes,
    required this.priorities,
    this.isLoading = false,
    this.error,
  });
  
  CustomTypesState copyWith({
    List<CustomTaskType>? taskTypes,
    List<CustomPriority>? priorities,
    bool? isLoading,
    String? error,
  }) {
    return CustomTypesState(
      taskTypes: taskTypes ?? this.taskTypes,
      priorities: priorities ?? this.priorities,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Custom Types State Notifier
class CustomTypesNotifier extends StateNotifier<CustomTypesState> {
  final CustomTypeLocalDataSource _dataSource;
  
  CustomTypesNotifier(this._dataSource) : super(CustomTypesState(
    taskTypes: CustomTaskType.defaults,
    priorities: CustomPriority.defaults,
  ));
  
  /// Initialize and load all types
  Future<void> init() async {
    state = state.copyWith(isLoading: true);
    try {
      await _dataSource.init();
      reload();
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
  
  /// Reload types from storage
  void reload() {
    try {
      final taskTypes = _dataSource.getAllTaskTypes();
      final priorities = _dataSource.getAllPriorities();
      state = state.copyWith(
        taskTypes: taskTypes,
        priorities: priorities,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
  
  // Task Type Management
  Future<void> addTaskType(String label, String emoji) async {
    try {
      final id = 'type_${DateTime.now().millisecondsSinceEpoch}';
      final sortOrder = state.taskTypes.length;
      final type = CustomTaskType(
        id: id,
        label: label,
        emoji: emoji,
        isDefault: false,
        sortOrder: sortOrder,
      );
      await _dataSource.addTaskType(type);
      reload();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  Future<void> updateTaskType(String id, String label, String emoji) async {
    try {
      final existing = _dataSource.getTaskType(id);
      if (existing != null) {
        final updated = existing.copyWith(label: label, emoji: emoji);
        await _dataSource.updateTaskType(updated);
        reload();
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  Future<bool> deleteTaskType(String id) async {
    try {
      // Check if this is the last type
      if (state.taskTypes.length <= 1) {
        state = state.copyWith(error: 'Cannot delete the last task type');
        return false;
      }
      await _dataSource.deleteTaskType(id);
      reload();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
  
  // Priority Management
  Future<void> addPriority(String label, String emoji, int colorValue) async {
    try {
      final id = 'priority_${DateTime.now().millisecondsSinceEpoch}';
      final sortOrder = state.priorities.length;
      final priority = CustomPriority(
        id: id,
        label: label,
        emoji: emoji,
        colorValue: colorValue,
        isDefault: false,
        sortOrder: sortOrder,
      );
      await _dataSource.addPriority(priority);
      reload();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  Future<void> updatePriority(String id, String label, String emoji, int colorValue) async {
    try {
      final existing = _dataSource.getPriority(id);
      if (existing != null) {
        final updated = existing.copyWith(label: label, emoji: emoji, colorValue: colorValue);
        await _dataSource.updatePriority(updated);
        reload();
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  Future<bool> deletePriority(String id) async {
    try {
      // Check if this is the last priority
      if (state.priorities.length <= 1) {
        state = state.copyWith(error: 'Cannot delete the last priority');
        return false;
      }
      await _dataSource.deletePriority(id);
      reload();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
  
  // Reset
  Future<void> resetAll() async {
    try {
      await _dataSource.resetTaskTypes();
      await _dataSource.resetPriorities();
      reload();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

/// Custom Types Provider
final customTypesProvider = StateNotifierProvider<CustomTypesNotifier, CustomTypesState>((ref) {
  final dataSource = ref.watch(customTypeLocalDataSourceProvider);
  return CustomTypesNotifier(dataSource);
});
