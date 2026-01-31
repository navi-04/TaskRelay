import '../datasources/day_summary_local_datasource.dart';
import '../models/day_summary_entity.dart';
import '../models/task_entity.dart';
import '../../core/utils/date_utils.dart';

/// Repository for DaySummary operations
/// 
/// This repository manages day summaries which are cached aggregations
/// of daily task statistics for performance optimization
class DaySummaryRepository {
  final DaySummaryLocalDataSource _dataSource;
  
  DaySummaryRepository(this._dataSource);
  
  /// Get summary for a date
  DaySummaryEntity? getSummaryForDate(String date) {
    return _dataSource.getSummaryForDate(date);
  }
  
  /// Get summaries for date range
  Map<String, DaySummaryEntity> getSummariesInRange(String startDate, String endDate) {
    return _dataSource.getSummariesInRange(startDate, endDate);
  }
  
  /// Calculate and save summary for a date based on tasks
  /// 
  /// This is called whenever tasks change for a date
  Future<DaySummaryEntity> calculateAndSaveSummary(
    String date, 
    List<TaskEntity> tasks,
  ) async {
    final totalTasks = tasks.length;
    final completedTasks = tasks.where((t) => t.isCompleted).length;
    final totalWeight = tasks.fold(0, (sum, t) => sum + t.weight);
    final completedWeight = tasks
        .where((t) => t.isCompleted)
        .fold(0, (sum, t) => sum + t.weight);
    final carriedOverTasks = tasks.where((t) => t.isCarriedOver).length;
    
    final summary = DaySummaryEntity(
      date: date,
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      totalWeight: totalWeight,
      completedWeight: completedWeight,
      carriedOverTasks: carriedOverTasks,
      isFullyCompleted: totalTasks > 0 && completedTasks == totalTasks,
      hasTasks: totalTasks > 0,
      lastUpdated: DateTime.now(),
    );
    
    await _dataSource.saveSummary(summary);
    return summary;
  }
  
  /// Get summary for today
  DaySummaryEntity? getTodaySummary() {
    final today = DateHelper.formatDate(DateHelper.getToday());
    return getSummaryForDate(today);
  }
  
  /// Get summaries for current month
  List<DaySummaryEntity> getCurrentMonthSummaries() {
    final now = DateTime.now();
    return _dataSource.getSummariesForMonth(now.year, now.month);
  }
  
  /// Get summaries for a specific month
  List<DaySummaryEntity> getSummariesForMonth(int year, int month) {
    return _dataSource.getSummariesForMonth(year, month);
  }
  
  /// Calculate completion streak
  /// 
  /// Streak is the number of consecutive days where all tasks were completed
  /// Breaks if:
  /// - Any day has incomplete tasks
  /// - Any day has carried over tasks that remain incomplete
  int calculateStreak() {
    final today = DateHelper.getToday();
    int streak = 0;
    
    // Start from yesterday and go backwards
    DateTime currentDate = today.subtract(const Duration(days: 1));
    
    while (true) {
      final dateString = DateHelper.formatDate(currentDate);
      final summary = getSummaryForDate(dateString);
      
      // If no summary exists or no tasks for that day, break
      if (summary == null || !summary.hasTasks) {
        break;
      }
      
      // If day is fully completed, increment streak
      if (summary.isFullyCompleted) {
        streak++;
        currentDate = currentDate.subtract(const Duration(days: 1));
      } else {
        // Streak is broken
        break;
      }
    }
    
    return streak;
  }
  
  /// Get weekly completion statistics
  Map<String, dynamic> getWeeklyStats() {
    final today = DateHelper.getToday();
    final weekAgo = today.subtract(const Duration(days: 7));
    
    final startDate = DateHelper.formatDate(weekAgo);
    final endDate = DateHelper.formatDate(today);
    
    final summaries = getSummariesInRange(startDate, endDate).values.toList();
    
    final totalDays = summaries.where((s) => s.hasTasks).length;
    final completedDays = summaries.where((s) => s.isFullyCompleted).length;
    final totalTasks = summaries.fold(0, (sum, s) => sum + s.totalTasks);
    final completedTasks = summaries.fold(0, (sum, s) => sum + s.completedTasks);
    final missedTasks = totalTasks - completedTasks;
    
    final completionPercentage = totalTasks > 0 
        ? (completedTasks / totalTasks) * 100 
        : 0.0;
    
    final averageDailyLoad = totalDays > 0 
        ? totalTasks / totalDays 
        : 0.0;
    
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
  
  /// Delete summary for date
  Future<void> deleteSummary(String date) async {
    await _dataSource.deleteSummary(date);
  }
  
  /// Rebuild all summaries (useful after bulk task changes)
  Future<void> rebuildAllSummaries(Map<String, List<TaskEntity>> tasksByDate) async {
    final summaries = <DaySummaryEntity>[];
    
    for (var entry in tasksByDate.entries) {
      final date = entry.key;
      final tasks = entry.value;
      
      final totalTasks = tasks.length;
      final completedTasks = tasks.where((t) => t.isCompleted).length;
      final totalWeight = tasks.fold(0, (sum, t) => sum + t.weight);
      final completedWeight = tasks
          .where((t) => t.isCompleted)
          .fold(0, (sum, t) => sum + t.weight);
      final carriedOverTasks = tasks.where((t) => t.isCarriedOver).length;
      
      summaries.add(DaySummaryEntity(
        date: date,
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        totalWeight: totalWeight,
        completedWeight: completedWeight,
        carriedOverTasks: carriedOverTasks,
        isFullyCompleted: totalTasks > 0 && completedTasks == totalTasks,
        hasTasks: totalTasks > 0,
        lastUpdated: DateTime.now(),
      ));
    }
    
    await _dataSource.saveSummaries(summaries);
  }
}
