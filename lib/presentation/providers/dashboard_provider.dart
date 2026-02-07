import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/day_summary_entity.dart';
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
  });
  
  factory DashboardStats.empty(String todayDate, int dailyLimitMinutes) {
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
    
    return DashboardStats(
      todayDate: today,
      todaySummary: todaySummary,
      streak: streak,
      weeklyStats: weeklyStats,
      dailyLimitMinutes: settings.dailyTimeLimitMinutes,
      usedMinutes: usedMinutes,
      remainingMinutes: remainingMinutes,
      progressPercentage: progressPercentage,
      isOverLimit: isOverLimit,
    );
  } catch (e) {
    // Return empty stats if box not initialized yet
    final settings = ref.watch(settingsProvider);
    final today = DateHelper.formatDate(DateHelper.getToday());
    return DashboardStats.empty(today, settings.dailyTimeLimitMinutes);
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
