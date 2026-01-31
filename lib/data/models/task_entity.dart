import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';
import 'task_type.dart';
import 'task_priority.dart';

part 'task_entity.g.dart';

/// Task Entity - Represents a single task
/// 
/// This entity stores all task information including:
/// - Basic info: title, description, weight
/// - Status: completion status
/// - Dates: created date, original date, current date
/// - Carry-over tracking: whether task was carried over
@HiveType(typeId: 0)
class TaskEntity extends Equatable {
  /// Unique identifier for the task
  @HiveField(0)
  final String id;
  
  /// Task title
  @HiveField(1)
  final String title;
  
  /// Optional task description
  @HiveField(2)
  final String? description;
  
  /// Task weight (used for daily limit calculation)
  @HiveField(3)
  final int weight;
  
  /// Whether the task is completed
  @HiveField(4)
  final bool isCompleted;
  
  /// Date when task was created (yyyy-MM-dd format)
  @HiveField(5)
  final String createdDate;
  
  /// Original date the task was assigned to (yyyy-MM-dd format)
  @HiveField(6)
  final String originalDate;
  
  /// Current date the task belongs to (yyyy-MM-dd format)
  /// This changes when task is carried over
  @HiveField(7)
  final String currentDate;
  
  /// Whether this task was carried over from a previous date
  @HiveField(8)
  final bool isCarriedOver;
  
  /// Timestamp when task was completed (null if not completed)
  @HiveField(9)
  final DateTime? completedAt;

  /// Task type (similar to Jira issue types)
  @HiveField(10)
  final TaskType taskType;

  /// Task priority level
  @HiveField(11)
  final TaskPriority priority;

  /// Additional notes or comments
  @HiveField(12)
  final String? notes;

  /// Tags for categorization
  @HiveField(13)
  final List<String> tags;

  const TaskEntity({
    required this.id,
    required this.title,
    this.description,
    required this.weight,
    required this.isCompleted,
    required this.createdDate,
    required this.originalDate,
    required this.currentDate,
    this.isCarriedOver = false,
    this.completedAt,
    this.taskType = TaskType.task,
    this.priority = TaskPriority.medium,
    this.notes,
    this.tags = const [],
  });
  
  /// Create a new task
  factory TaskEntity.create({
    required String id,
    required String title,
    String? description,
    required int weight,
    required String date,
    TaskType taskType = TaskType.task,
    TaskPriority priority = TaskPriority.medium,
    String? notes,
    List<String> tags = const [],
  }) {
    return TaskEntity(
      id: id,
      title: title,
      description: description,
      weight: weight,
      isCompleted: false,
      createdDate: date,
      originalDate: date,
      currentDate: date,
      isCarriedOver: false,
      taskType: taskType,
      priority: priority,
      notes: notes,
      tags: tags,
    );
  }
  
  /// Copy with method for immutable updates
  TaskEntity copyWith({
    String? id,
    String? title,
    String? description,
    int? weight,
    bool? isCompleted,
    String? createdDate,
    String? originalDate,
    String? currentDate,
    bool? isCarriedOver,
    DateTime? completedAt,
    TaskType? taskType,
    TaskPriority? priority,
    String? notes,
    List<String>? tags,
  }) {
    return TaskEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      weight: weight ?? this.weight,
      isCompleted: isCompleted ?? this.isCompleted,
      createdDate: createdDate ?? this.createdDate,
      originalDate: originalDate ?? this.originalDate,
      currentDate: currentDate ?? this.currentDate,
      isCarriedOver: isCarriedOver ?? this.isCarriedOver,
      completedAt: completedAt ?? this.completedAt,
      taskType: taskType ?? this.taskType,
      priority: priority ?? this.priority,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
    );
  }
  
  /// Mark task as completed
  TaskEntity markCompleted() {
    return copyWith(
      isCompleted: true,
      completedAt: DateTime.now(),
    );
  }
  
  /// Mark task as incomplete
  TaskEntity markIncomplete() {
    return copyWith(
      isCompleted: false,
      completedAt: null,
    );
  }
  
  /// Carry over task to a new date
  TaskEntity carryOverToDate(String newDate) {
    return copyWith(
      currentDate: newDate,
      isCarriedOver: true,
    );
  }
  
  @override
  List<Object?> get props => [
        id,
        title,
        description,
        weight,
        isCompleted,
        createdDate,
        originalDate,
        currentDate,
        isCarriedOver,
        completedAt,
        taskType,
        priority,
        notes,
        tags,
      ];
}
