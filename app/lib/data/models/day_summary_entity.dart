import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'day_summary_entity.g.dart';

/// Day Summary Entity - Aggregated statistics for a specific day
/// 
/// This entity caches daily statistics to optimize performance:
/// - Task counts and completion status
/// - Time/duration calculations
/// - Streak tracking
@HiveType(typeId: 2)
class DaySummaryEntity extends Equatable {
  /// Date this summary is for (yyyy-MM-dd format)
  @HiveField(0)
  final String date;
  
  /// Total number of tasks for this day
  @HiveField(1)
  final int totalTasks;
  
  /// Number of completed tasks
  @HiveField(2)
  final int completedTasks;
  
  /// Total duration of all tasks in minutes
  @HiveField(3)
  final int totalMinutes;
  
  /// Duration of completed tasks in minutes
  @HiveField(4)
  final int completedMinutes;
  
  /// Number of carried over tasks
  @HiveField(5)
  final int carriedOverTasks;
  
  /// Whether all tasks for this day are completed
  @HiveField(6)
  final bool isFullyCompleted;
  
  /// Whether this day had any tasks
  @HiveField(7)
  final bool hasTasks;
  
  /// Last update timestamp
  @HiveField(8)
  final DateTime lastUpdated;
  
  const DaySummaryEntity({
    required this.date,
    required this.totalTasks,
    required this.completedTasks,
    required this.totalMinutes,
    required this.completedMinutes,
    required this.carriedOverTasks,
    required this.isFullyCompleted,
    required this.hasTasks,
    required this.lastUpdated,
  });
  
  /// Create empty summary
  factory DaySummaryEntity.empty(String date) {
    return DaySummaryEntity(
      date: date,
      totalTasks: 0,
      completedTasks: 0,
      totalMinutes: 0,
      completedMinutes: 0,
      carriedOverTasks: 0,
      isFullyCompleted: false,
      hasTasks: false,
      lastUpdated: DateTime.now(),
    );
  }
  
  /// Calculate completion percentage (0-100)
  double get completionPercentage {
    if (totalTasks == 0) return 0;
    return (completedTasks / totalTasks) * 100;
  }
  
  /// Calculate time percentage used (0-100)
  double timePercentage(int dailyLimitMinutes) {
    if (dailyLimitMinutes == 0) return 0;
    return (totalMinutes / dailyLimitMinutes) * 100;
  }
  
  /// Get remaining time capacity in minutes (minimum 0)
  int remainingMinutes(int dailyLimitMinutes) {
    final remaining = dailyLimitMinutes - totalMinutes;
    return remaining < 0 ? 0 : remaining;
  }
  
  /// Check if day is over capacity
  bool isOverCapacity(int dailyLimitMinutes) {
    return totalMinutes > dailyLimitMinutes;
  }
  
  /// Get formatted total time string
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
  
  /// Get day status for calendar coloring
  DayStatus get dayStatus {
    if (!hasTasks) return DayStatus.noTasks;
    if (isFullyCompleted) return DayStatus.completed;
    if (completedTasks > 0) return DayStatus.partial;
    return DayStatus.missed;
  }
  
  /// Copy with method
  DaySummaryEntity copyWith({
    String? date,
    int? totalTasks,
    int? completedTasks,
    int? totalMinutes,
    int? completedMinutes,
    int? carriedOverTasks,
    bool? isFullyCompleted,
    bool? hasTasks,
    DateTime? lastUpdated,
  }) {
    return DaySummaryEntity(
      date: date ?? this.date,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      completedMinutes: completedMinutes ?? this.completedMinutes,
      carriedOverTasks: carriedOverTasks ?? this.carriedOverTasks,
      isFullyCompleted: isFullyCompleted ?? this.isFullyCompleted,
      hasTasks: hasTasks ?? this.hasTasks,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
  
  @override
  List<Object?> get props => [
        date,
        totalTasks,
        completedTasks,
        totalMinutes,
        completedMinutes,
        carriedOverTasks,
        isFullyCompleted,
        hasTasks,
        lastUpdated,
      ];
}

/// Enum representing the status of a day
enum DayStatus {
  noTasks,    // No tasks for this day
  completed,  // All tasks completed (green)
  partial,    // Some tasks completed (yellow)
  missed,     // No tasks completed (red)
}
