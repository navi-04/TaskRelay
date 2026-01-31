import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'day_summary_entity.g.dart';

/// Day Summary Entity - Aggregated statistics for a specific day
/// 
/// This entity caches daily statistics to optimize performance:
/// - Task counts and completion status
/// - Weight calculations
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
  
  /// Total weight of all tasks
  @HiveField(3)
  final int totalWeight;
  
  /// Weight of completed tasks
  @HiveField(4)
  final int completedWeight;
  
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
    required this.totalWeight,
    required this.completedWeight,
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
      totalWeight: 0,
      completedWeight: 0,
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
  
  /// Calculate weight percentage used (0-100)
  double weightPercentage(int dailyLimit) {
    if (dailyLimit == 0) return 0;
    return (totalWeight / dailyLimit) * 100;
  }
  
  /// Get remaining weight capacity
  int remainingWeight(int dailyLimit) {
    return dailyLimit - totalWeight;
  }
  
  /// Check if day is over capacity
  bool isOverCapacity(int dailyLimit) {
    return totalWeight > dailyLimit;
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
    int? totalWeight,
    int? completedWeight,
    int? carriedOverTasks,
    bool? isFullyCompleted,
    bool? hasTasks,
    DateTime? lastUpdated,
  }) {
    return DaySummaryEntity(
      date: date ?? this.date,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      totalWeight: totalWeight ?? this.totalWeight,
      completedWeight: completedWeight ?? this.completedWeight,
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
        totalWeight,
        completedWeight,
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
