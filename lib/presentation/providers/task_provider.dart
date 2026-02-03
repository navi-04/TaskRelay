import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/task_entity.dart';
import '../../data/models/task_type.dart';
import '../../data/models/task_priority.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/day_summary_repository.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/services/task_carry_over_service.dart';
import 'providers.dart';

/// Task State
class TaskState {
  final List<TaskEntity> tasks;
  final bool isLoading;
  final String? error;
  final String selectedDate;
  
  TaskState({
    required this.tasks,
    this.isLoading = false,
    this.error,
    required this.selectedDate,
  });
  
  TaskState copyWith({
    List<TaskEntity>? tasks,
    bool? isLoading,
    String? error,
    String? selectedDate,
  }) {
    return TaskState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedDate: selectedDate ?? this.selectedDate,
    );
  }
  
  List<TaskEntity> get pendingTasks => tasks.where((t) => !t.isCompleted).toList();
  List<TaskEntity> get completedTasks => tasks.where((t) => t.isCompleted).toList();
  List<TaskEntity> get carriedOverTasks => tasks.where((t) => t.isCarriedOver).toList();
  
  int get totalMinutes => tasks.fold(0, (sum, t) => sum + t.durationMinutes);
  int get completedMinutes => completedTasks.fold(0, (sum, t) => sum + t.durationMinutes);
  int get pendingMinutes => pendingTasks.fold(0, (sum, t) => sum + t.durationMinutes);
  
  /// Get formatted total time
  String get formattedTotalTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }
}

/// Task State Notifier
class TaskStateNotifier extends StateNotifier<TaskState> {
  final TaskRepository _taskRepository;
  final DaySummaryRepository _summaryRepository;
  final TaskCarryOverService _carryOverService;
  
  TaskStateNotifier(
    this._taskRepository,
    this._summaryRepository,
    this._carryOverService,
  ) : super(TaskState(
          tasks: [],
          selectedDate: DateHelper.formatDate(DateHelper.getToday()),
        ));
  
  /// Load tasks for currently selected date
  void loadTasksForSelectedDate() {
    state = state.copyWith(isLoading: true);
    
    try {
      final tasks = _taskRepository.getTasksForDate(state.selectedDate);
      state = state.copyWith(
        tasks: tasks,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      // If box not initialized yet, keep empty state
      state = state.copyWith(
        tasks: [],
        isLoading: false,
        error: null,
      );
    }
  }
  
  /// Load tasks for today (resets selected date to today)
  void loadTasksForToday() {
    final today = DateHelper.formatDate(DateHelper.getToday());
    state = state.copyWith(selectedDate: today);
    loadTasksForSelectedDate();
  }
  
  /// Process carry-over and refresh tasks
  Future<CarryOverResult> processCarryOverAndRefresh() async {
    try {
      final result = await _carryOverService.processCarryOver();
      // Refresh tasks after carry-over
      loadTasksForSelectedDate();
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return CarryOverResult(carriedCount: 0, totalMinutes: 0, dates: []);
    }
  }
  
  /// Change selected date
  void selectDate(String date) {
    state = state.copyWith(selectedDate: date);
    loadTasksForSelectedDate();
  }
  
  /// Add a new task
  Future<void> addTask({
    required String id,
    required String title,
    String? description,
    required int durationMinutes,
    TaskType taskType = TaskType.task,
    TaskPriority priority = TaskPriority.medium,
    String? notes,
    List<String> tags = const [],
  }) async {
    try {
      final task = TaskEntity.create(
        id: id,
        title: title,
        description: description,
        durationMinutes: durationMinutes,
        date: state.selectedDate,
        taskType: taskType,
        priority: priority,
        notes: notes,
        tags: tags,
      );
      
      await _taskRepository.addTask(task);
      await _updateSummary();
      loadTasksForSelectedDate();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  /// Update task
  Future<void> updateTask(TaskEntity task) async {
    try {
      await _taskRepository.updateTask(task);
      await _updateSummary();
      loadTasksForSelectedDate();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  /// Delete task
  Future<void> deleteTask(String id) async {
    try {
      await _taskRepository.deleteTask(id);
      await _updateSummary();
      loadTasksForSelectedDate();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  /// Toggle task completion
  Future<void> toggleTaskCompletion(String id) async {
    try {
      await _taskRepository.toggleTaskCompletion(id);
      await _updateSummary();
      loadTasksForSelectedDate();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
  
  /// Update summary for current date
  Future<void> _updateSummary() async {
    final tasks = _taskRepository.getTasksForDate(state.selectedDate);
    await _summaryRepository.calculateAndSaveSummary(state.selectedDate, tasks);
  }
  
  /// Check if adding duration would exceed limit
  bool wouldExceedLimit(int durationMinutes, int dailyLimitMinutes) {
    return _taskRepository.wouldExceedLimit(state.selectedDate, durationMinutes, dailyLimitMinutes);
  }
  
  /// Delete all tasks in date range
  Future<int> deleteTasksInDateRange(String startDate, String endDate) async {
    try {
      final count = await _taskRepository.deleteTasksInDateRange(startDate, endDate);
      
      // Update summaries for affected dates
      await _updateSummariesInRange(startDate, endDate);
      
      loadTasksForSelectedDate();
      return count;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return 0;
    }
  }
  
  /// Update summaries for date range after deletion
  Future<void> _updateSummariesInRange(String startDate, String endDate) async {
    try {
      // Parse dates to iterate through range
      final start = DateHelper.parseDate(startDate);
      final end = DateHelper.parseDate(endDate);
      
      for (var date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
        final dateStr = DateHelper.formatDate(date);
        final tasks = _taskRepository.getTasksForDate(dateStr);
        await _summaryRepository.calculateAndSaveSummary(dateStr, tasks);
      }
    } catch (e) {
      // Silently fail summary update
    }
  }
  
  /// Get tasks in date range (for preview)
  List<TaskEntity> getTasksInDateRange(String startDate, String endDate) {
    return _taskRepository.getTasksInDateRange(startDate, endDate);
  }
  
  /// Clear all tasks
  Future<void> clearAllTasks() async {
    try {
      await _taskRepository.clearAllTasks();
      state = state.copyWith(tasks: []);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

/// Task State Provider
final taskStateProvider = StateNotifierProvider<TaskStateNotifier, TaskState>((ref) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final summaryRepo = ref.watch(daySummaryRepositoryProvider);
  final carryOverService = ref.watch(taskCarryOverServiceProvider);
  
  return TaskStateNotifier(taskRepo, summaryRepo, carryOverService);
});
