import '../datasources/task_local_datasource.dart';
import '../models/task_entity.dart';
import '../../core/utils/date_utils.dart';

/// Repository for Task operations
/// 
/// This repository handles all task-related business logic including:
/// - CRUD operations
/// - Task carry-over logic
/// - Task filtering and retrieval
class TaskRepository {
  final TaskLocalDataSource _dataSource;
  
  TaskRepository(this._dataSource);
  
  /// Get all tasks
  List<TaskEntity> getAllTasks() {
    return _dataSource.getAllTasks();
  }
  
  /// Get tasks for a specific date
  List<TaskEntity> getTasksForDate(String date) {
    try {
      return _dataSource.getTasksForDate(date);
    } catch (e) {
      // If box not initialized, return empty list
      return [];
    }
  }
  
  /// Get task by ID
  TaskEntity? getTaskById(String id) {
    try {
      return _dataSource.getTaskById(id);
    } catch (e) {
      return null;
    }
  }
  
  /// Add a new task
  Future<void> addTask(TaskEntity task) async {
    await _dataSource.addTask(task);
  }
  
  /// Update a task
  Future<void> updateTask(TaskEntity task) async {
    await _dataSource.updateTask(task);
  }
  
  /// Delete a task
  Future<void> deleteTask(String id) async {
    await _dataSource.deleteTask(id);
  }
  
  /// Toggle task completion status
  Future<void> toggleTaskCompletion(String id) async {
    final task = _dataSource.getTaskById(id);
    if (task != null) {
      final updatedTask = task.isCompleted 
          ? task.markIncomplete() 
          : task.markCompleted();
      await _dataSource.updateTask(updatedTask);
    }
  }
  
  /// Get incomplete tasks before a specific date
  List<TaskEntity> getIncompleteTasksBeforeDate(String date) {
    return _dataSource.getIncompleteTasksBeforeDate(date);
  }
  
  /// Carry over incomplete tasks from previous dates to target date
  /// 
  /// This is the CORE carry-over logic:
  /// 1. Find all incomplete tasks before the target date
  /// 2. Update each task's currentDate to the target date
  /// 3. Mark them as carried over
  /// 4. Save all updates in bulk
  Future<List<TaskEntity>> carryOverTasksToDate(String targetDate) async {
    // Get all incomplete tasks before target date
    final incompleteTasks = getIncompleteTasksBeforeDate(targetDate);
    
    if (incompleteTasks.isEmpty) {
      return [];
    }
    
    // Update each task to carry over to target date
    final carriedTasks = incompleteTasks.map((task) {
      return task.carryOverToDate(targetDate);
    }).toList();
    
    // Bulk update all carried tasks
    await _dataSource.updateTasks(carriedTasks);
    
    return carriedTasks;
  }
  
  /// Carry over incomplete tasks to today
  Future<List<TaskEntity>> carryOverTasksToToday() async {
    final today = DateHelper.formatDate(DateHelper.getToday());
    return await carryOverTasksToDate(today);
  }
  
  /// Process carry-over for multiple days
  /// 
  /// This handles the scenario when app is closed for multiple days:
  /// - Carries over tasks day by day, not directly to today
  /// - Maintains proper carry-over chain
  Future<void> processMultiDayCarryOver(String fromDate, String toDate) async {
    final startDate = DateHelper.parseDate(fromDate);
    final endDate = DateHelper.parseDate(toDate);
    
    DateTime currentDate = startDate.add(const Duration(days: 1));
    
    while (currentDate.isBefore(endDate) || DateHelper.isSameDay(currentDate, endDate)) {
      final dateString = DateHelper.formatDate(currentDate);
      await carryOverTasksToDate(dateString);
      currentDate = currentDate.add(const Duration(days: 1));
    }
  }
  
  /// Get total duration for a specific date in minutes
  int getTotalMinutesForDate(String date) {
    try {
      final tasks = getTasksForDate(date);
      return tasks.fold(0, (sum, task) => sum + task.durationMinutes);
    } catch (e) {
      // If box not initialized, return 0
      return 0;
    }
  }
  
  /// Get completed duration for a specific date in minutes
  int getCompletedMinutesForDate(String date) {
    final tasks = getTasksForDate(date);
    return tasks
        .where((task) => task.isCompleted)
        .fold(0, (sum, task) => sum + task.durationMinutes);
  }
  
  /// Check if adding a task would exceed daily time limit
  bool wouldExceedLimit(String date, int taskDurationMinutes, int dailyLimitMinutes) {
    try {
      final currentMinutes = getTotalMinutesForDate(date);
      return (currentMinutes + taskDurationMinutes) > dailyLimitMinutes;
    } catch (e) {
      // If box not initialized, allow the task (return false)
      return false;
    }
  }
  
  /// Get carried over tasks for a date
  List<TaskEntity> getCarriedOverTasksForDate(String date) {
    return getTasksForDate(date).where((task) => task.isCarriedOver).toList();
  }
  
  /// Get all recurring (permanent) tasks
  List<TaskEntity> getRecurringTasks() {
    try {
      return _dataSource.getRecurringTasks();
    } catch (e) {
      return [];
    }
  }

  /// Get all permanent tasks (backward compat alias)
  List<TaskEntity> getPermanentTasks() {
    return getRecurringTasks();
  }
  
  /// Get tasks in date range
  List<TaskEntity> getTasksInDateRange(String startDate, String endDate) {
    return _dataSource.getTasksInDateRange(startDate, endDate);
  }
  
  /// Delete all tasks in date range
  Future<int> deleteTasksInDateRange(String startDate, String endDate) async {
    return await _dataSource.deleteTasksInDateRange(startDate, endDate);
  }
  
  /// Clear all tasks
  Future<void> clearAllTasks() async {
    await _dataSource.clearAllTasks();
  }
}
