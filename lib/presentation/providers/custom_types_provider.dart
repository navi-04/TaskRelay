import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../../data/models/custom_task_type.dart';
import '../../data/models/task_type.dart';
import '../../data/models/task_priority.dart';
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

  /// Get the display label for a TaskType enum value.
  /// Uses the custom label if the user has renamed it, otherwise falls back to enum label.
  String taskTypeLabel(TaskType type) {
    for (final ct in taskTypes) {
      if (ct.id == type.name) return ct.label;
    }
    return type.label;
  }

  /// Get the display label for a TaskPriority enum value.
  /// Uses the custom label if the user has renamed it, otherwise falls back to enum label.
  String priorityLabel(TaskPriority priority) {
    for (final cp in priorities) {
      if (cp.id == priority.name) return cp.label;
    }
    return priority.label;
  }

  /// Get the display color for a TaskPriority enum value.
  /// Uses the custom color if the user has changed it, otherwise falls back to enum color.
  Color priorityColor(TaskPriority priority) {
    for (final cp in priorities) {
      if (cp.id == priority.name) return Color(cp.colorValue);
    }
    return priority.color;
  }

  // ---- ID-based lookups (used by the new string-ID architecture) ----

  /// Find a CustomTaskType by its ID.
  CustomTaskType? findTaskType(String id) {
    for (final ct in taskTypes) {
      if (ct.id == id) return ct;
    }
    return null;
  }

  /// Find a CustomPriority by its ID.
  CustomPriority? findPriority(String id) {
    for (final cp in priorities) {
      if (cp.id == id) return cp;
    }
    return null;
  }

  /// Get the display label for a task type by its string ID.
  String taskTypeLabelById(String id) {
    final ct = findTaskType(id);
    if (ct != null) return ct.label;
    // Fallback: try to match an enum by name
    try {
      final enumVal = TaskType.values.firstWhere((t) => t.name == id);
      return enumVal.label;
    } catch (_) {
      return id; // last resort
    }
  }

  /// Get the display label for a priority by its string ID.
  String priorityLabelById(String id) {
    final cp = findPriority(id);
    if (cp != null) return cp.label;
    try {
      final enumVal = TaskPriority.values.firstWhere((p) => p.name == id);
      return enumVal.label;
    } catch (_) {
      return id;
    }
  }

  /// Get the display color for a priority by its string ID.
  Color priorityColorById(String id) {
    final cp = findPriority(id);
    if (cp != null) return Color(cp.colorValue);
    try {
      final enumVal = TaskPriority.values.firstWhere((p) => p.name == id);
      return enumVal.color;
    } catch (_) {
      return const Color(0xFF9E9E9E); // grey fallback
    }
  }

  /// Resolve a task type string ID to its best-matching TaskType enum value.
  /// Returns TaskType.task as default if no match.
  TaskType resolveTaskTypeEnum(String id) {
    try {
      return TaskType.values.firstWhere((t) => t.name == id);
    } catch (_) {
      return TaskType.task;
    }
  }

  /// Resolve a priority string ID to its best-matching TaskPriority enum value.
  /// Returns TaskPriority.medium as default if no match.
  TaskPriority resolvePriorityEnum(String id) {
    try {
      return TaskPriority.values.firstWhere((p) => p.name == id);
    } catch (_) {
      return TaskPriority.medium;
    }
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
