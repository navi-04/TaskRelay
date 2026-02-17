import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/task_entity.dart';
import '../../data/models/task_type.dart';
import '../../data/models/task_priority.dart';
import '../../data/models/estimation_mode.dart';
import '../../data/models/reminder_type.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/day_summary_repository.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/services/task_carry_over_service.dart';
import '../../domain/services/notification_service.dart';
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

  /// Get the used value for a given estimation mode
  int usedValueFor(EstimationMode mode) {
    switch (mode) {
      case EstimationMode.timeBased:
        return totalMinutes;
      case EstimationMode.countBased:
        return tasks.length;
    }
  }

  /// Get completed value for a given estimation mode
  int completedValueFor(EstimationMode mode) {
    switch (mode) {
      case EstimationMode.timeBased:
        return completedMinutes;
      case EstimationMode.countBased:
        return completedTasks.length;
    }
  }
  
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
  final NotificationService _notificationService;
  
  TaskStateNotifier(
    this._taskRepository,
    this._summaryRepository,
    this._carryOverService,
    this._notificationService,
  ) : super(TaskState(
          tasks: [],
          selectedDate: DateHelper.formatDate(DateHelper.getToday()),
        ));
  
  /// Load tasks for currently selected date
  void loadTasksForSelectedDate({bool showLoading = false}) async {
    if (showLoading) {
      state = state.copyWith(isLoading: true);
    }
    
    try {
      // Get date-specific tasks (non-recurring tasks for this date)
      final dateTasks = _taskRepository.getTasksForDate(state.selectedDate)
          .where((task) => !task.isRecurring)
          .toList();
      
      // Get recurring tasks - only for dates within their range and not deleted
      final recurringTasks = _taskRepository.getRecurringTasks();
      
      // Update recurring tasks for the selected date
      final updatedRecurringTasks = <TaskEntity>[];
      for (final task in recurringTasks) {
        // Determine effective start/end dates
        final startDate = task.recurringStartDate ?? task.createdDate;
        final endDate = task.recurringEndDate;
        
        // Only show if selected date is within [startDate, endDate] range
        if (state.selectedDate.compareTo(startDate) < 0) continue;
        if (endDate != null && state.selectedDate.compareTo(endDate) > 0) continue;
        
        // Skip if this date has been individually deleted
        if (task.deletedDates.contains(state.selectedDate)) continue;
        
        // Derive per-date completion from completedDates list.
        // Do NOT mutate isCompleted on the stored entity — that destroys
        // completion info for other dates.
        final isCompletedForDate = task.completedDates.contains(state.selectedDate);
        final viewTask = task.copyWith(
          currentDate: state.selectedDate,
          isCompleted: isCompletedForDate,
        );
        updatedRecurringTasks.add(viewTask);
      }
      
      // Combine both lists
      final allTasks = [...dateTasks, ...updatedRecurringTasks];
      
      // Re-schedule alarms for recurring tasks — ONLY when viewing today.
      // Scheduling alarms when browsing other dates would cancel today's
      // alarms (since each task has only one alarm slot keyed by task ID).
      final todayStr = DateHelper.formatDate(DateHelper.getToday());
      if (state.selectedDate == todayStr) {
        for (final task in updatedRecurringTasks) {
          if (task.alarmTime != null && !task.isCompleted) {
            await _scheduleRecurringAlarmForNextValidDate(task);
          }
        }
      }
      
      state = state.copyWith(
        tasks: allTasks,
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
    loadTasksForSelectedDate(showLoading: true);
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
    loadTasksForSelectedDate(showLoading: true);
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
    bool isPermanent = false,
    bool isRecurring = false,
    DateTime? alarmTime,
    int reminderTypeIndex = 0,
    String? recurringStartDate,
    String? recurringEndDate,
    String? taskTypeId,
    String? priorityId,
  }) async {
    try {
      final effectiveRecurring = isRecurring || isPermanent;
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
        isPermanent: effectiveRecurring,
        alarmTime: alarmTime,
        reminderTypeIndex: reminderTypeIndex,
        recurringStartDate: recurringStartDate,
        recurringEndDate: recurringEndDate,
        taskTypeId: taskTypeId,
        priorityId: priorityId,
      );
      
      await _taskRepository.addTask(task);
      
      // Schedule alarm/notification if alarmTime is set
      if (alarmTime != null) {
        try {
          final hasPermissions = await _notificationService.areNotificationsEnabled();
          if (!hasPermissions) {
            await _notificationService.requestPermissions();
          }
          final taskDate = DateHelper.parseDate(state.selectedDate);
          if (ReminderType.fromIndex(reminderTypeIndex) == ReminderType.fullAlarm) {
            await _notificationService.scheduleTaskAlarm(
              taskId: id,
              taskTitle: title,
              alarmTime: alarmTime,
              isPermanent: effectiveRecurring,
              taskDate: taskDate,
            );
          } else {
            await _notificationService.scheduleTaskNotification(
              taskId: id,
              taskTitle: title,
              alarmTime: alarmTime,
              isPermanent: effectiveRecurring,
              taskDate: taskDate,
            );
          }
        } catch (_) {
          // Alarm scheduling failed — continue, task is already saved
        }
      }
      
      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Update task
  Future<void> updateTask(TaskEntity task) async {
    try {
      // Get old task to check if alarm changed
      final oldTask = state.tasks.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );
      
      await _taskRepository.updateTask(task);
      
      // Handle alarm updates
      try {
        if (task.alarmTime != null) {
          final hasPermissions = await _notificationService.areNotificationsEnabled();
          if (!hasPermissions) {
            await _notificationService.requestPermissions();
          }
          final taskDate = DateHelper.parseDate(task.currentDate);
          if (task.reminderType == ReminderType.fullAlarm) {
            await _notificationService.scheduleTaskAlarm(
              taskId: task.id,
              taskTitle: task.title,
              alarmTime: task.alarmTime!,
              isPermanent: task.isPermanent,
              taskDate: taskDate,
            );
          } else {
            await _notificationService.scheduleTaskNotification(
              taskId: task.id,
              taskTitle: task.title,
              alarmTime: task.alarmTime!,
              isPermanent: task.isPermanent,
              taskDate: taskDate,
            );
          }
        } else if (oldTask.alarmTime != null && task.alarmTime == null) {
          await _notificationService.cancelTaskAlarm(task.id);
        }
      } catch (_) {
        // Alarm update failed — continue, task data is already saved
      }
      
      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Delete task
  Future<void> deleteTask(String id) async {
    try {
      // Cancel alarm if exists
      await _notificationService.cancelTaskAlarm(id);
      
      await _taskRepository.deleteTask(id);
      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Delete a recurring task for a single date only (hides it on that day)
  Future<void> deleteRecurringTaskForDate(String id, String date) async {
    try {
      final task = state.tasks.firstWhere((t) => t.id == id);
      final updatedDeletedDates = [...task.deletedDates, date];
      final updatedTask = task.copyWith(deletedDates: updatedDeletedDates);
      await _taskRepository.updateTask(updatedTask);

      // Reschedule alarm for the next valid date (in case the deleted date
      // was the day the alarm was scheduled for)
      if (task.isRecurring && task.alarmTime != null) {
        await _scheduleRecurringAlarmForNextValidDate(updatedTask);
      }

      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Delete a recurring task from a given date onwards (sets end date)
  Future<void> deleteRecurringTaskFromDate(String id, String fromDate) async {
    try {
      final task = state.tasks.firstWhere((t) => t.id == id);
      final startDate = task.recurringStartDate ?? task.createdDate;
      
      // If deleting from the start date, delete entirely
      if (fromDate.compareTo(startDate) <= 0) {
        await _notificationService.cancelTaskAlarm(id);
        await _taskRepository.deleteTask(id);
      } else {
        // Set end date to day before fromDate
        final from = DateHelper.parseDate(fromDate);
        final dayBefore = from.subtract(const Duration(days: 1));
        final endDateStr = DateHelper.formatDate(dayBefore);
        await _taskRepository.updateTask(task.copyWith(
          recurringEndDate: endDateStr,
        ));
      }
      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Mute alarm for a recurring task for today only.
  /// Cancels the scheduled alarm and adds today to mutedAlarmDates,
  /// but keeps alarmTime so it rings again on future days.
  Future<void> muteAlarmForToday(String id) async {
    try {
      final task = state.tasks.firstWhere((t) => t.id == id);
      await _notificationService.cancelTaskAlarm(id);
      
      final mutedDates = [...task.mutedAlarmDates];
      if (!mutedDates.contains(state.selectedDate)) {
        mutedDates.add(state.selectedDate);
      }
      final updatedTask = task.copyWith(mutedAlarmDates: mutedDates);
      await _taskRepository.updateTask(updatedTask);

      // For recurring tasks, schedule alarm for the next valid day
      if (task.isRecurring) {
        await _scheduleRecurringAlarmForNextValidDate(
          updatedTask,
          startFromTomorrow: true,
        );
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Clear alarm for a task permanently (all days).
  /// Cancels the scheduled alarm and removes alarmTime from the entity.
  Future<void> clearAlarmForAll(String id) async {
    try {
      final task = state.tasks.firstWhere((t) => t.id == id);
      await _notificationService.cancelTaskAlarm(id);
      
      await _taskRepository.updateTask(task.copyWith(
        alarmTime: null,
        mutedAlarmDates: const [],
      ));
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }

  /// Schedule the alarm for the next valid date for a recurring task.
  ///
  /// Reads the task's alarm data (stored in Hive) and finds the next day
  /// that is within the recurring range, not deleted, and not muted.
  /// If [startFromTomorrow] is true, today is skipped (used after
  /// dismiss/mute/completion so we don't re-trigger today's alarm).
  Future<void> _scheduleRecurringAlarmForNextValidDate(
    TaskEntity task, {
    bool startFromTomorrow = false,
  }) async {
    if (!task.isRecurring || task.alarmTime == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var checkDate = startFromTomorrow
        ? today.add(const Duration(days: 1))
        : today;

    // If starting from today, skip if alarm time has already passed
    if (!startFromTomorrow) {
      final todayAlarmTime = DateTime(
        today.year, today.month, today.day,
        task.alarmTime!.hour, task.alarmTime!.minute,
      );
      if (todayAlarmTime.isBefore(now)) {
        checkDate = today.add(const Duration(days: 1));
      }
    }

    final startDate = task.recurringStartDate ?? task.createdDate;
    final endDate = task.recurringEndDate;

    // Search up to 365 days ahead for the next valid alarm day
    for (int i = 0; i < 365; i++) {
      final dateStr = DateHelper.formatDate(checkDate);

      // Past the recurring end date — no more alarms
      if (endDate != null && dateStr.compareTo(endDate) > 0) return;

      // Within range, not deleted, not muted → schedule here
      if (dateStr.compareTo(startDate) >= 0 &&
          !task.deletedDates.contains(dateStr) &&
          !task.mutedAlarmDates.contains(dateStr)) {
        try {
          if (task.reminderType == ReminderType.fullAlarm) {
            await _notificationService.scheduleTaskAlarm(
              taskId: task.id,
              taskTitle: task.title,
              alarmTime: task.alarmTime!,
              isPermanent: task.isPermanent,
              taskDate: checkDate,
            );
          } else {
            await _notificationService.scheduleTaskNotification(
              taskId: task.id,
              taskTitle: task.title,
              alarmTime: task.alarmTime!,
              isPermanent: task.isPermanent,
              taskDate: checkDate,
            );
          }
        } catch (_) {}
        return;
      }

      checkDate = checkDate.add(const Duration(days: 1));
    }
  }

  /// Ensure all recurring tasks have their alarms properly scheduled.
  ///
  /// Reads alarm data from Hive (user data) and schedules the next valid
  /// alarm for every recurring task. Call on app startup to recover from
  /// reboots, process death, or missed rescheduling.
  Future<void> ensureRecurringAlarmsScheduled() async {
    try {
      final recurringTasks = _taskRepository.getRecurringTasks();
      for (final task in recurringTasks) {
        if (task.alarmTime != null) {
          await _scheduleRecurringAlarmForNextValidDate(task);
        }
      }
    } catch (_) {}
  }

  /// Handle alarm dismissal — clears alarmTime for non-recurring tasks
  /// and mutes for today for recurring tasks.
  /// Called when the user taps "Dismiss" on the alarm UI.
  Future<void> handleAlarmDismissal(String id) async {
    try {
      // Look up the task from the repository (might not be in current state
      // if the selected date differs from the task's date)
      final task = _taskRepository.getTaskById(id);
      if (task == null) return;

      await _notificationService.cancelTaskAlarm(id);

      if (task.isRecurring) {
        // For recurring tasks: mute alarm for today only
        final today = DateHelper.formatDate(DateHelper.getToday());
        final mutedDates = [...task.mutedAlarmDates];
        if (!mutedDates.contains(today)) {
          mutedDates.add(today);
        }
        final updatedTask = task.copyWith(mutedAlarmDates: mutedDates);
        await _taskRepository.updateTask(updatedTask);

        // Schedule alarm for the next valid day so it rings tomorrow
        await _scheduleRecurringAlarmForNextValidDate(
          updatedTask,
          startFromTomorrow: true,
        );
      } else {
        // For non-recurring tasks: clear alarmTime entirely
        await _taskRepository.updateTask(task.copyWith(
          alarmTime: null,
        ));
      }
    } catch (_) {
      // Task not found or update failed — ignore
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Toggle task completion
  Future<void> toggleTaskCompletion(String id) async {
    try {
      // Find the task
      final task = state.tasks.firstWhere((t) => t.id == id);

      // Determine current completion state for this date
      final selectedDate = state.selectedDate;
      final bool currentlyCompleted = task.isRecurring
          ? task.isCompletedForDate(selectedDate)
          : task.isCompleted;

      if (task.isRecurring) {
        // --- Recurring task: toggle via completedDates ---
        final completedDates = [...task.completedDates];
        final mutedDates = [...task.mutedAlarmDates];

        if (!currentlyCompleted) {
          // Mark DONE for this date
          if (!completedDates.contains(selectedDate)) {
            completedDates.add(selectedDate);
          }
          if (!mutedDates.contains(selectedDate)) {
            mutedDates.add(selectedDate);
          }
          await _taskRepository.updateTask(task.copyWith(
            completedDates: completedDates,
            mutedAlarmDates: mutedDates,
          ));

          // Cancel alarm and schedule next valid day
          try {
            if (task.alarmTime != null) {
              await _notificationService.cancelTaskAlarm(id);
              await _scheduleRecurringAlarmForNextValidDate(
                task.copyWith(completedDates: completedDates, mutedAlarmDates: mutedDates),
                startFromTomorrow: true,
              );
            }
          } catch (_) {}
        } else {
          // Mark INCOMPLETE for this date
          completedDates.remove(selectedDate);
          mutedDates.remove(selectedDate);
          await _taskRepository.updateTask(task.copyWith(
            completedDates: completedDates,
            mutedAlarmDates: mutedDates,
          ));

          // Re-schedule alarm if applicable
          try {
            if (task.alarmTime != null) {
              final hasPermissions = await _notificationService.areNotificationsEnabled();
              if (!hasPermissions) {
                await _notificationService.requestPermissions();
              }
              final taskDate = DateHelper.parseDate(selectedDate);
              if (task.reminderType == ReminderType.fullAlarm) {
                await _notificationService.scheduleTaskAlarm(
                  taskId: task.id,
                  taskTitle: task.title,
                  alarmTime: task.alarmTime!,
                  isPermanent: task.isPermanent,
                  taskDate: taskDate,
                );
              } else {
                await _notificationService.scheduleTaskNotification(
                  taskId: task.id,
                  taskTitle: task.title,
                  alarmTime: task.alarmTime!,
                  isPermanent: task.isPermanent,
                  taskDate: taskDate,
                );
              }
            }
          } catch (_) {}
        }
      } else {
        // --- Non-recurring task: use isCompleted as before ---
        await _taskRepository.toggleTaskCompletion(id);

        try {
          if (!currentlyCompleted && task.alarmTime != null) {
            // Marking DONE → cancel alarm and clear alarmTime
            await _notificationService.cancelTaskAlarm(id);
            await _taskRepository.updateTask(task.copyWith(
              isCompleted: true,
              completedAt: DateTime.now(),
              alarmTime: null,
            ));
          } else if (currentlyCompleted && task.alarmTime != null) {
            // Marking INCOMPLETE → re-schedule alarm
            final hasPermissions = await _notificationService.areNotificationsEnabled();
            if (!hasPermissions) {
              await _notificationService.requestPermissions();
            }
            final taskDate = DateHelper.parseDate(task.currentDate);
            if (task.reminderType == ReminderType.fullAlarm) {
              await _notificationService.scheduleTaskAlarm(
                taskId: task.id,
                taskTitle: task.title,
                alarmTime: task.alarmTime!,
                isPermanent: task.isPermanent,
                taskDate: taskDate,
              );
            } else {
              await _notificationService.scheduleTaskNotification(
                taskId: task.id,
                taskTitle: task.title,
                alarmTime: task.alarmTime!,
                isPermanent: task.isPermanent,
                taskDate: taskDate,
              );
            }
          }
        } catch (_) {
          // Alarm update failed — continue
        }
      }
      
      await _updateSummary();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      loadTasksForSelectedDate();
    }
  }
  
  /// Update summary for current date.
  /// Includes both date-specific tasks AND recurring tasks visible on this date.
  Future<void> _updateSummary() async {
    await _updateSummaryForDate(state.selectedDate);
  }

  /// Build the full task list for a given date (including recurring tasks)
  /// and save the summary.
  Future<void> _updateSummaryForDate(String date) async {
    // Non-recurring tasks for this date
    final dateTasks = _taskRepository.getTasksForDate(date)
        .where((t) => !t.isRecurring)
        .toList();

    // Recurring tasks that should appear on this date
    final recurringTasks = _taskRepository.getRecurringTasks();
    final recurringForDate = <TaskEntity>[];
    for (final task in recurringTasks) {
      final startDate = task.recurringStartDate ?? task.createdDate;
      final endDate = task.recurringEndDate;
      if (date.compareTo(startDate) < 0) continue;
      if (endDate != null && date.compareTo(endDate) > 0) continue;
      if (task.deletedDates.contains(date)) continue;

      // Derive correct completion state for this date
      final isCompletedForDate = task.completedDates.contains(date);
      recurringForDate.add(task.copyWith(
        isCompleted: isCompletedForDate,
      ));
    }

    final allTasks = [...dateTasks, ...recurringForDate];
    await _summaryRepository.calculateAndSaveSummary(date, allTasks);
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
        await _updateSummaryForDate(dateStr);
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
  final notificationService = ref.watch(notificationServiceProvider);
  
  return TaskStateNotifier(taskRepo, summaryRepo, carryOverService, notificationService);
});
