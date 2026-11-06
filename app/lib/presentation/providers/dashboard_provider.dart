import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/day_summary_entity.dart';
import '../../data/models/task_entity.dart';
import '../../data/models/estimation_mode.dart';
import '../../core/utils/date_utils.dart';
import 'providers.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

/// Dashboard Stats
class DashboardStats {
  final String todayDate;
  final DaySummaryEntity? todaySummary;
  final int streak;
  final Map<String, dynamic> weeklyStats;
  final int dailyLimitMinutes;
  final int usedMinutes;
  final int remainingMinutes;
  final double progressPercentage;
  final bool isOverLimit;
  final EstimationMode estimationMode;
  final int dailyLimit;   // generic limit for current mode
  final int usedValue;    // generic used for current mode
  final int remainingValue;
  
  DashboardStats({
    required this.todayDate,
    this.todaySummary,
    required this.streak,
    required this.weeklyStats,
    required this.dailyLimitMinutes,
    required this.usedMinutes,
    required this.remainingMinutes,
    required this.progressPercentage,
    required this.isOverLimit,
    this.estimationMode = EstimationMode.timeBased,
    this.dailyLimit = 0,
    this.usedValue = 0,
    this.remainingValue = 0,
  });
  
  factory DashboardStats.empty(String todayDate, int dailyLimitMinutes, {EstimationMode estimationMode = EstimationMode.timeBased, int dailyLimit = 0}) {
    return DashboardStats(
      todayDate: todayDate,
      todaySummary: null,
      streak: 0,
      weeklyStats: {},
      dailyLimitMinutes: dailyLimitMinutes,
      usedMinutes: 0,
      remainingMinutes: dailyLimitMinutes,
      progressPercentage: 0.0,
      isOverLimit: false,
      estimationMode: estimationMode,
      dailyLimit: dailyLimit,
      usedValue: 0,
      remainingValue: dailyLimit,
    );
  }
  
  /// Get formatted used time
  String get formattedUsedTime {
    final hours = usedMinutes ~/ 60;
    final mins = usedMinutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }
  
  /// Get formatted remaining time
  String get formattedRemainingTime {
    if (remainingMinutes <= 0) return '0m';
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
  
  /// Get formatted daily limit
  String get formattedDailyLimit {
    final hours = dailyLimitMinutes ~/ 60;
    final mins = dailyLimitMinutes % 60;
    if (hours > 0 && mins > 0) {
      return '${hours}h ${mins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${mins}m';
    }
  }

  /// Format a value based on current estimation mode
  String formatValue(int value) {
    switch (estimationMode) {
      case EstimationMode.timeBased:
        final h = value ~/ 60;
        final m = value % 60;
        if (h > 0 && m > 0) return '${h}h ${m}m';
        if (h > 0) return '${h}h';
        return '${m}m';
      case EstimationMode.countBased:
        return '$value';
    }
  }

  String get formattedUsedValue => formatValue(usedValue);
  String get formattedRemainingValue => formatValue(remainingValue);
  String get formattedDailyLimitValue => formatValue(dailyLimit);

  String get progressLabel {
    switch (estimationMode) {
      case EstimationMode.timeBased:
        return 'Time Used';
      case EstimationMode.countBased:
        return 'Tasks Added';
    }
  }
}

/// Dashboard Provider - Rebuilds when tasks or settings change
final dashboardProvider = Provider<DashboardStats>((ref) {
  try {
    final summaryRepo = ref.watch(daySummaryRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    // Watch task state to trigger rebuilds when tasks change
    final taskState = ref.watch(taskStateProvider);
    
    final today = DateHelper.formatDate(DateHelper.getToday());
    
    final taskRepo = ref.watch(taskRepositoryProvider);

    // Re-read from repository to get fresh data
    final todaySummary = summaryRepo.getSummaryForDate(today);
    final streak = summaryRepo.calculateStreak();

    // Compute weekly stats on-the-fly so recurring tasks are included
    final weeklyStats = _computeWeeklyStats(taskRepo, summaryRepo);
    
    // Use task state for today's minutes if viewing today
    final usedMinutes = taskState.selectedDate == today 
        ? taskState.totalMinutes 
        : (todaySummary?.totalMinutes ?? 0);
    // Clamp to 0 minimum (can't have negative remaining time)
    final remainingMinutes = (settings.dailyTimeLimitMinutes - usedMinutes).clamp(0, settings.dailyTimeLimitMinutes);

    // Mode-aware values
    final mode = settings.estimationMode;
    final dailyLimit = settings.effectiveDailyLimit;
    final usedValue = taskState.usedValueFor(mode);
    final remainingValue = (dailyLimit - usedValue).clamp(0, dailyLimit);

    // Compute progress from mode-aware values
    final modeProgressPercentage = dailyLimit > 0
        ? ((usedValue / dailyLimit) * 100).clamp(0.0, 100.0)
        : 0.0;
    final modeIsOverLimit = usedValue > dailyLimit;
    
    return DashboardStats(
      todayDate: today,
      todaySummary: todaySummary,
      streak: streak,
      weeklyStats: weeklyStats,
      dailyLimitMinutes: settings.dailyTimeLimitMinutes,
      usedMinutes: usedMinutes,
      remainingMinutes: remainingMinutes,
      progressPercentage: modeProgressPercentage,
      isOverLimit: modeIsOverLimit,
      estimationMode: mode,
      dailyLimit: dailyLimit,
      usedValue: usedValue,
      remainingValue: remainingValue,
    );
  } catch (e) {
    // Return empty stats if box not initialized yet
    final settings = ref.watch(settingsProvider);
    final today = DateHelper.formatDate(DateHelper.getToday());
    return DashboardStats.empty(today, settings.dailyTimeLimitMinutes,
        estimationMode: settings.estimationMode,
        dailyLimit: settings.effectiveDailyLimit);
  }
});

/// Build a [DaySummaryEntity] for [dateStr] by combining non-recurring tasks
/// with recurring tasks that are active on that date.
/// Future dates are excluded from recurring-task counting so they never
/// appear as "missed" before the day has actually arrived.
DaySummaryEntity _buildSummaryForDate(
  String dateStr,
  List<TaskEntity> dateSpecificTasks,
  List<TaskEntity> recurringTasks,
) {
  // Never include recurring tasks for future dates
  final todayStr = DateHelper.formatDate(DateHelper.getToday());
  final isFutureDate = dateStr.compareTo(todayStr) > 0;

  // Non-recurring tasks for this date
  final dateTasks = dateSpecificTasks.where((t) => !t.isRecurring).toList();

  // Recurring tasks active on this date (skip for future dates)
  final recurringForDate = <TaskEntity>[];
  if (!isFutureDate) {
    for (final task in recurringTasks) {
      final startDate = task.recurringStartDate ?? task.createdDate;
      final endDate = task.recurringEndDate;
      if (dateStr.compareTo(startDate) < 0) continue;
      if (endDate != null && dateStr.compareTo(endDate) > 0) continue;
      if (task.deletedDates.contains(dateStr)) continue;

      final isCompletedForDate = task.completedDates.contains(dateStr);
      recurringForDate.add(task.copyWith(isCompleted: isCompletedForDate));
    }
  }

  final allTasks = [...dateTasks, ...recurringForDate];

  if (allTasks.isEmpty) {
    return DaySummaryEntity.empty(dateStr);
  }

  final totalTasks = allTasks.length;
  final completedTasks = allTasks.where((t) => t.isCompleted).length;
  final totalMinutes = allTasks.fold(0, (sum, t) => sum + t.durationMinutes);
  final completedMinutes =
      allTasks.where((t) => t.isCompleted).fold(0, (sum, t) => sum + t.durationMinutes);
  final carriedOverTasks = allTasks.where((t) => t.isCarriedOver).length;

  return DaySummaryEntity(
    date: dateStr,
    totalTasks: totalTasks,
    completedTasks: completedTasks,
    totalMinutes: totalMinutes,
    completedMinutes: completedMinutes,
    carriedOverTasks: carriedOverTasks,
    isFullyCompleted: completedTasks == totalTasks,
    hasTasks: true,
    lastUpdated: DateTime.now(),
  );
}

/// Compute weekly stats on-the-fly so that recurring tasks are always included.
Map<String, dynamic> _computeWeeklyStats(
  dynamic taskRepo,
  dynamic summaryRepo,
) {
  final todayDt = DateHelper.getToday();
  final weekAgo = todayDt.subtract(const Duration(days: 7));
  final recurringTasks = taskRepo.getRecurringTasks() as List<TaskEntity>;

  int totalDays = 0;
  int completedDays = 0;
  int totalTasks = 0;
  int completedTasks = 0;

  for (var d = weekAgo.add(const Duration(days: 1));
      !d.isAfter(todayDt);
      d = d.add(const Duration(days: 1))) {
    final dateStr = DateHelper.formatDate(d);
    final dateSpecific =
        (taskRepo.getTasksForDate(dateStr) as List<TaskEntity>);
    final summary =
        _buildSummaryForDate(dateStr, dateSpecific, recurringTasks);
    if (summary.hasTasks) {
      totalDays++;
      if (summary.isFullyCompleted) completedDays++;
      totalTasks += summary.totalTasks;
      completedTasks += summary.completedTasks;
    }
  }

  final missedTasks = totalTasks - completedTasks;
  final completionPercentage =
      totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0;
  final averageDailyLoad = totalDays > 0 ? totalTasks / totalDays : 0.0;

  return {
    'totalDays': totalDays,
    'completedDays': completedDays,
    'totalTasks': totalTasks,
    'completedTasks': completedTasks,
    'missedTasks': missedTasks,
    'completionPercentage': completionPercentage,
    'averageDailyLoad': averageDailyLoad,
  };
}

/// Calendar Data Provider - Computes summaries on-the-fly so recurring tasks
/// are always reflected correctly (completed / partial / missed).
final calendarDataProvider = Provider.family.autoDispose<Map<String, DaySummaryEntity>, DateTime>((ref, date) {
  try {
    final taskRepo = ref.watch(taskRepositoryProvider);

    // Watch task state to trigger rebuilds when tasks change
    ref.watch(taskStateProvider);

    final startOfMonth = DateHelper.getStartOfMonth(date);
    final endOfMonth = DateHelper.getEndOfMonth(date);
    // Never compute summaries for future dates — they haven't happened yet
    final today = DateHelper.getToday();
    final lastDay = endOfMonth.isAfter(today) ? today : endOfMonth;

    final recurringTasks = taskRepo.getRecurringTasks();
    final result = <String, DaySummaryEntity>{};

    for (var day = startOfMonth;
        !day.isAfter(lastDay);
        day = day.add(const Duration(days: 1))) {
      final dateStr = DateHelper.formatDate(day);
      final dateSpecific = taskRepo.getTasksForDate(dateStr);
      final summary =
          _buildSummaryForDate(dateStr, dateSpecific, recurringTasks);
      if (summary.hasTasks) {
        result[dateStr] = summary;
      }
    }

    return result;
  } catch (e) {
    // Return empty map if box not initialized yet
    return {};
  }
});
