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
  final int dailyLimit;
  final int usedWeight;
  final int remainingWeight;
  final double progressPercentage;
  final bool isOverLimit;
  
  DashboardStats({
    required this.todayDate,
    this.todaySummary,
    required this.streak,
    required this.weeklyStats,
    required this.dailyLimit,
    required this.usedWeight,
    required this.remainingWeight,
    required this.progressPercentage,
    required this.isOverLimit,
  });
  
  factory DashboardStats.empty(String todayDate, int dailyLimit) {
    return DashboardStats(
      todayDate: todayDate,
      todaySummary: null,
      streak: 0,
      weeklyStats: {},
      dailyLimit: dailyLimit,
      usedWeight: 0,
      remainingWeight: dailyLimit,
      progressPercentage: 0.0,
      isOverLimit: false,
    );
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
    
    // Use task state for today's weight if viewing today
    final usedWeight = taskState.selectedDate == today 
        ? taskState.totalWeight 
        : (todaySummary?.totalWeight ?? 0);
    final remainingWeight = settings.dailyWeightLimit - usedWeight;
    final progressPercentage = settings.dailyWeightLimit > 0
        ? (usedWeight / settings.dailyWeightLimit) * 100
        : 0.0;
    final isOverLimit = usedWeight > settings.dailyWeightLimit;
    
    return DashboardStats(
      todayDate: today,
      todaySummary: todaySummary,
      streak: streak,
      weeklyStats: weeklyStats,
      dailyLimit: settings.dailyWeightLimit,
      usedWeight: usedWeight,
      remainingWeight: remainingWeight,
      progressPercentage: progressPercentage,
      isOverLimit: isOverLimit,
    );
  } catch (e) {
    // Return empty stats if box not initialized yet
    final settings = ref.watch(settingsProvider);
    final today = DateHelper.formatDate(DateHelper.getToday());
    return DashboardStats.empty(today, settings.dailyWeightLimit);
  }
});

/// Calendar Data Provider
final calendarDataProvider = Provider.family<Map<String, DaySummaryEntity>, DateTime>((ref, date) {
  try {
    final summaryRepo = ref.watch(daySummaryRepositoryProvider);
    
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
