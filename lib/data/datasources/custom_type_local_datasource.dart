import 'package:hive/hive.dart';
import '../models/custom_task_type.dart';

/// Data source for custom task types and priorities
class CustomTypeLocalDataSource {
  static const String _taskTypesBoxName = 'custom_task_types';
  static const String _prioritiesBoxName = 'custom_priorities';
  
  Box<CustomTaskType>? _taskTypesBox;
  Box<CustomPriority>? _prioritiesBox;
  
  bool _isInitialized = false;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    _taskTypesBox = await Hive.openBox<CustomTaskType>(_taskTypesBoxName);
    _prioritiesBox = await Hive.openBox<CustomPriority>(_prioritiesBoxName);
    
    // Initialize with defaults if empty
    if (_taskTypesBox!.isEmpty) {
      for (var type in CustomTaskType.defaults) {
        await _taskTypesBox!.put(type.id, type);
      }
    }
    
    if (_prioritiesBox!.isEmpty) {
      for (var priority in CustomPriority.defaults) {
        await _prioritiesBox!.put(priority.id, priority);
      }
    }
    
    _isInitialized = true;
  }
  
  // Task Types
  List<CustomTaskType> getAllTaskTypes() {
    if (_taskTypesBox == null) return CustomTaskType.defaults;
    final types = _taskTypesBox!.values.toList();
    types.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return types;
  }
  
  CustomTaskType? getTaskType(String id) {
    return _taskTypesBox?.get(id);
  }
  
  Future<void> addTaskType(CustomTaskType type) async {
    await _taskTypesBox?.put(type.id, type);
  }
  
  Future<void> updateTaskType(CustomTaskType type) async {
    await _taskTypesBox?.put(type.id, type);
  }
  
  Future<void> deleteTaskType(String id) async {
    // Don't allow deleting if it's the last one
    if (_taskTypesBox != null && _taskTypesBox!.length > 1) {
      await _taskTypesBox?.delete(id);
    }
  }
  
  // Priorities
  List<CustomPriority> getAllPriorities() {
    if (_prioritiesBox == null) return CustomPriority.defaults;
    final priorities = _prioritiesBox!.values.toList();
    priorities.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return priorities;
  }
  
  CustomPriority? getPriority(String id) {
    return _prioritiesBox?.get(id);
  }
  
  Future<void> addPriority(CustomPriority priority) async {
    await _prioritiesBox?.put(priority.id, priority);
  }
  
  Future<void> updatePriority(CustomPriority priority) async {
    await _prioritiesBox?.put(priority.id, priority);
  }
  
  Future<void> deletePriority(String id) async {
    // Don't allow deleting if it's the last one
    if (_prioritiesBox != null && _prioritiesBox!.length > 1) {
      await _prioritiesBox?.delete(id);
    }
  }
  
  // Reset to defaults
  Future<void> resetTaskTypes() async {
    await _taskTypesBox?.clear();
    for (var type in CustomTaskType.defaults) {
      await _taskTypesBox?.put(type.id, type);
    }
  }
  
  Future<void> resetPriorities() async {
    await _prioritiesBox?.clear();
    for (var priority in CustomPriority.defaults) {
      await _prioritiesBox?.put(priority.id, priority);
    }
  }
}
