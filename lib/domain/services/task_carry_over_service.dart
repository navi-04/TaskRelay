import '../../data/repositories/task_repository.dart';
import '../../data/repositories/day_summary_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../core/utils/date_utils.dart';
import 'notification_service.dart';

/// Task Carry-Over Service
/// 
/// CORE BUSINESS LOGIC for intelligent task carry-over:
/// 
/// 1. Detects when app hasn't been opened for multiple days
/// 2. Carries over incomplete tasks day by day (not directly to today)
/// 3. Maintains proper carry-over chain
/// 4. Updates day summaries after carry-over
/// 5. Sends notifications if enabled
/// 
/// This service should be called on app startup to ensure
/// all pending tasks are properly carried over.
class TaskCarryOverService {
  final TaskRepository _taskRepository;
  final DaySummaryRepository _summaryRepository;
  final SettingsRepository _settingsRepository;
  final NotificationService _notificationService;
  
  TaskCarryOverService(
    this._taskRepository,
    this._summaryRepository,
    this._settingsRepository,
    this._notificationService,
  );
  
  /// Process all pending carry-overs
  /// 
  /// This is the main entry point called on app startup
  /// It handles:
  /// - Single day carry-over
  /// - Multi-day carry-over (when app closed for multiple days)
  /// - Summary updates
  /// - Notifications
  Future<CarryOverResult> processCarryOver() async {
    final today = DateHelper.getToday();
    final todayString = DateHelper.formatDate(today);
    
    // Get all incomplete tasks before today
    final incompleteTasks = _taskRepository.getIncompleteTasksBeforeDate(todayString);
    
    if (incompleteTasks.isEmpty) {
      return CarryOverResult(
        carriedCount: 0,
        totalMinutes: 0,
        dates: [],
      );
    }
    
    // Find the earliest date with incomplete tasks
    String? earliestDate;
    for (var task in incompleteTasks) {
      if (earliestDate == null || task.currentDate.compareTo(earliestDate) < 0) {
        earliestDate = task.currentDate;
      }
    }
    
    if (earliestDate == null) {
      return CarryOverResult(
        carriedCount: 0,
        totalMinutes: 0,
        dates: [],
      );
    }
    
    final earliestDateTime = DateHelper.parseDate(earliestDate);
    final daysDifference = today.difference(earliestDateTime).inDays;
    
    // If only 1 day difference, do simple carry-over
    if (daysDifference == 1) {
      return await _processSingleDayCarryOver(earliestDate, todayString);
    }
    
    // If multiple days, process day by day
    return await _processMultiDayCarryOver(earliestDate, todayString, daysDifference);
  }
  
  /// Process carry-over for a single day gap
  Future<CarryOverResult> _processSingleDayCarryOver(
    String fromDate,
    String toDate,
  ) async {
    final carriedTasks = await _taskRepository.carryOverTasksToDate(toDate);
    
    if (carriedTasks.isEmpty) {
      return CarryOverResult(
        carriedCount: 0,
        totalMinutes: 0,
        dates: [],
      );
    }
    
    final totalMinutes = carriedTasks.fold(0, (sum, task) => sum + task.durationMinutes);
    
    // Update today's summary
    await _updateSummaryForDate(toDate);
    
    // Send notification if enabled
    await _sendCarryOverNotification(carriedTasks.length, totalMinutes);
    
    return CarryOverResult(
      carriedCount: carriedTasks.length,
      totalMinutes: totalMinutes,
      dates: [fromDate, toDate],
    );
  }
  
  /// Process carry-over when app was closed for multiple days
  /// 
  /// This maintains proper carry-over chain by processing day by day
  /// instead of jumping directly to today
  Future<CarryOverResult> _processMultiDayCarryOver(
    String startDate,
    String endDate,
    int daysDifference,
  ) async {
    print('Processing multi-day carry-over: $daysDifference days');
    
    final processedDates = <String>[];
    DateTime currentDate = DateHelper.parseDate(startDate);
    final endDateTime = DateHelper.parseDate(endDate);
    
    int totalCarriedCount = 0;
    int totalMinutes = 0;
    
    // Process each day sequentially
    while (currentDate.isBefore(endDateTime)) {
      final nextDate = currentDate.add(const Duration(days: 1));
      final nextDateString = DateHelper.formatDate(nextDate);
      
      final carriedTasks = await _taskRepository.carryOverTasksToDate(nextDateString);
      
      if (carriedTasks.isNotEmpty) {
        totalCarriedCount = carriedTasks.length;
        totalMinutes = carriedTasks.fold(0, (sum, task) => sum + task.durationMinutes);
        processedDates.add(nextDateString);
        
        // Update summary for this date
        await _updateSummaryForDate(nextDateString);
      }
      
      currentDate = nextDate;
    }
    
    // Send notification for final carry-over to today
    if (totalCarriedCount > 0) {
      await _sendCarryOverNotification(totalCarriedCount, totalMinutes);
    }
    
    return CarryOverResult(
      carriedCount: totalCarriedCount,
      totalMinutes: totalMinutes,
      dates: processedDates,
    );
  }
  
  /// Update day summary after tasks change
  Future<void> _updateSummaryForDate(String date) async {
    final tasks = _taskRepository.getTasksForDate(date);
    await _summaryRepository.calculateAndSaveSummary(date, tasks);
  }
  
  /// Send carry-over notification if enabled
  Future<void> _sendCarryOverNotification(int count, int totalMinutes) async {
    final settings = _settingsRepository.getSettings();
    
    if (settings.notificationsEnabled && settings.showCarryOverAlerts) {
      await _notificationService.showCarryOverAlert(
        carriedCount: count,
        totalMinutes: totalMinutes,
      );
    }
  }
  
  /// Schedule daily reminder based on current settings
  Future<void> scheduleDailyReminder() async {
    final settings = _settingsRepository.getSettings();
    
    if (!settings.notificationsEnabled) {
      await _notificationService.cancelDailyReminder();
      return;
    }
    
    final today = DateHelper.formatDate(DateHelper.getToday());
    final todayTasks = _taskRepository.getTasksForDate(today);
    final pendingTasks = todayTasks.where((t) => !t.isCompleted).toList();
    final totalMinutes = pendingTasks.fold(0, (sum, t) => sum + t.durationMinutes);
    final carriedOver = pendingTasks.where((t) => t.isCarriedOver).length;
    
    await _notificationService.scheduleDailyReminder(
      hour: settings.notificationHour,
      minute: settings.notificationMinute,
      pendingTasksCount: pendingTasks.length,
      totalMinutes: totalMinutes,
      carriedOverCount: carriedOver,
    );
  }
  
  /// Check if today's load exceeds limit and provide suggestions
  Future<DailyLoadCheck> checkDailyLoad() async {
    final settings = _settingsRepository.getSettings();
    final today = DateHelper.formatDate(DateHelper.getToday());
    final todayTasks = _taskRepository.getTasksForDate(today);
    
    final totalMinutes = todayTasks.fold(0, (sum, t) => sum + t.durationMinutes);
    final carriedOverTasks = todayTasks.where((t) => t.isCarriedOver).toList();
    final carriedMinutes = carriedOverTasks.fold(0, (sum, t) => sum + t.durationMinutes);
    
    final isOverLimit = totalMinutes > settings.dailyTimeLimitMinutes;
    final remainingMinutes = settings.dailyTimeLimitMinutes - totalMinutes;
    
    // Helper to format minutes
    String formatTime(int mins) {
      final hours = mins ~/ 60;
      final minutes = mins % 60;
      if (hours > 0 && minutes > 0) {
        return '${hours}h ${minutes}m';
      } else if (hours > 0) {
        return '${hours}h';
      } else {
        return '${minutes}m';
      }
    }
    
    String? suggestion;
    if (isOverLimit && carriedOverTasks.isNotEmpty) {
      suggestion = 'Your carried-over tasks (${formatTime(carriedMinutes)}) '
          'exceed your daily limit. Consider rescheduling some tasks '
          'to future dates or breaking them into smaller tasks.';
    } else if (remainingMinutes < 30 && remainingMinutes > 0) {
      suggestion = 'You have limited capacity remaining (${formatTime(remainingMinutes)}). '
          'Avoid adding long tasks today.';
    }
    
    return DailyLoadCheck(
      totalMinutes: totalMinutes,
      dailyLimitMinutes: settings.dailyTimeLimitMinutes,
      remainingMinutes: remainingMinutes,
      isOverLimit: isOverLimit,
      carriedOverMinutes: carriedMinutes,
      suggestion: suggestion,
    );
  }
}

/// Result of carry-over operation
class CarryOverResult {
  final int carriedCount;
  final int totalMinutes;
  final List<String> dates;
  
  CarryOverResult({
    required this.carriedCount,
    required this.totalMinutes,
    required this.dates,
  });
  
  bool get hasCarriedTasks => carriedCount > 0;
  
  /// Get formatted time string
  String get formattedTime {
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

/// Daily load check result
class DailyLoadCheck {
  final int totalMinutes;
  final int dailyLimitMinutes;
  final int remainingMinutes;
  final bool isOverLimit;
  final int carriedOverMinutes;
  final String? suggestion;
  
  DailyLoadCheck({
    required this.totalMinutes,
    required this.dailyLimitMinutes,
    required this.remainingMinutes,
    required this.isOverLimit,
    required this.carriedOverMinutes,
    this.suggestion,
  });
  
  /// Get formatted time strings
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
  
  String get formattedRemainingTime {
    if (remainingMinutes < 0) return '0m';
    final hours = remainingMinutes ~/ 60;
    final mins = remainingMinutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }
}
