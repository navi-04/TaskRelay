import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/day_summary_entity.dart';
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
      case EstimationMode.weightBased:
        return '$value pts';
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
      case EstimationMode.weightBased:
        return 'Weight Used';
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
    
    // Re-read from repository to get fresh data
    final todaySummary = summaryRepo.getSummaryForDate(today);
    final streak = summaryRepo.calculateStreak();
    final weeklyStats = summaryRepo.getWeeklyStats();
    
    // Use task state for today's minutes if viewing today
    final usedMinutes = taskState.selectedDate == today 
        ? taskState.totalMinutes 
        : (todaySummary?.totalMinutes ?? 0);
    // Clamp to 0 minimum (can't have negative remaining time)
    final remainingMinutes = (settings.dailyTimeLimitMinutes - usedMinutes).clamp(0, settings.dailyTimeLimitMinutes);
    // Clamp to 100% maximum for display purposes
    final progressPercentage = settings.dailyTimeLimitMinutes > 0
        ? ((usedMinutes / settings.dailyTimeLimitMinutes) * 100).clamp(0.0, 100.0)
        : 0.0;
    final isOverLimit = usedMinutes > settings.dailyTimeLimitMinutes;

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

/// Calendar Data Provider - Watches task state for dynamic updates
final calendarDataProvider = Provider.family.autoDispose<Map<String, DaySummaryEntity>, DateTime>((ref, date) {
  try {
    final summaryRepo = ref.watch(daySummaryRepositoryProvider);
    
    // Watch task state to trigger rebuilds when tasks change
    ref.watch(taskStateProvider);
    
    final startOfMonth = DateHelper.getStartOfMonth(date);
    final endOfMonth = DateHelper.getEndOfMonth(date);
    
    final startDate = DateHelper.formatDate(startOfMonth);
    final endDate = DateHelper.formatDate(endOfMonth);
    
    return summaryRepo.getSummariesInRange(startDate, endDate);
  } catch (e) {
    // Return empty map if box not initialized yet
    return {};
  }
});
