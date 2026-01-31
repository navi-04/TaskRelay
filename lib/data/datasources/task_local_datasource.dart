import 'package:hive/hive.dart';
import '../models/task_entity.dart';

/// Local data source for Task operations using Hive
class TaskLocalDataSource {
  static const String _boxName = 'tasks_box';
  
  Box<TaskEntity>? _box;
  
  /// Initialize Hive box
  Future<void> init() async {
    try {
      _box = await Hive.openBox<TaskEntity>(_boxName);
    } catch (e) {
      // If box fails to open (likely due to schema changes), delete and recreate
      print('Error opening task box: $e');
      print('Deleting corrupted box and creating new one...');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<TaskEntity>(_boxName);
    }
  }
  
  Box<TaskEntity> get _taskBox {
    if (_box == null || !_box!.isOpen) {
      throw Exception('Task box not initialized. Call init() first.');
    }
    return _box!;
  }
  
  /// Get all tasks
  List<TaskEntity> getAllTasks() {
    return _taskBox.values.toList();
  }
  
  /// Get tasks for a specific date
  List<TaskEntity> getTasksForDate(String date) {
    return _taskBox.values
        .where((task) => task.currentDate == date)
        .toList();
  }
  
  /// Get task by ID
  TaskEntity? getTaskById(String id) {
    return _taskBox.values.firstWhere(
      (task) => task.id == id,
      orElse: () => throw Exception('Task not found'),
    );
  }
  
  /// Get tasks in date range
  List<TaskEntity> getTasksInDateRange(String startDate, String endDate) {
    return _taskBox.values
        .where((task) => 
            task.currentDate.compareTo(startDate) >= 0 &&
            task.currentDate.compareTo(endDate) <= 0)
        .toList();
  }
  
  /// Get all incomplete tasks before a date
  List<TaskEntity> getIncompleteTasksBeforeDate(String date) {
    return _taskBox.values
        .where((task) => 
            !task.isCompleted && 
            task.currentDate.compareTo(date) < 0)
        .toList();
  }
  
  /// Add a new task
  Future<void> addTask(TaskEntity task) async {
    await _taskBox.put(task.id, task);
  }
  
  /// Update existing task
  Future<void> updateTask(TaskEntity task) async {
    await _taskBox.put(task.id, task);
  }
  
  /// Delete task
  Future<void> deleteTask(String id) async {
    await _taskBox.delete(id);
  }
  
  /// Delete all tasks for a date
  Future<void> deleteTasksForDate(String date) async {
    final tasksToDelete = getTasksForDate(date);
    for (var task in tasksToDelete) {
      await _taskBox.delete(task.id);
    }
  }
  
  /// Bulk update tasks
  Future<void> updateTasks(List<TaskEntity> tasks) async {
    final Map<String, TaskEntity> taskMap = {
      for (var task in tasks) task.id: task
    };
    await _taskBox.putAll(taskMap);
  }
  
  /// Get completed tasks count
  int getCompletedTasksCount() {
    return _taskBox.values.where((task) => task.isCompleted).length;
  }
  
  /// Get carried over tasks
  List<TaskEntity> getCarriedOverTasks() {
    return _taskBox.values.where((task) => task.isCarriedOver).toList();
  }
  
  /// Clear all tasks (use with caution)
  Future<void> clearAllTasks() async {
    await _taskBox.clear();
  }
  
  /// Delete tasks in date range
  Future<int> deleteTasksInDateRange(String startDate, String endDate) async {
    final tasksToDelete = getTasksInDateRange(startDate, endDate);
    for (var task in tasksToDelete) {
      await _taskBox.delete(task.id);
    }
    return tasksToDelete.length;
  }
}
