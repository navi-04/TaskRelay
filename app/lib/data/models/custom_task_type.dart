import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'custom_task_type.g.dart';

/// Custom Task Type - User created task types
@HiveType(typeId: 5)
class CustomTaskType extends Equatable {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String label;
  
  @HiveField(2)
  final String emoji;
  
  @HiveField(3)
  final bool isDefault;
  
  @HiveField(4)
  final int sortOrder;
  
  const CustomTaskType({
    required this.id,
    required this.label,
    required this.emoji,
    this.isDefault = false,
    this.sortOrder = 0,
  });
  
  String get displayName => label;
  
  CustomTaskType copyWith({
    String? id,
    String? label,
    String? emoji,
    bool? isDefault,
    int? sortOrder,
  }) {
    return CustomTaskType(
      id: id ?? this.id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
  
  @override
  List<Object?> get props => [id, label, emoji, isDefault, sortOrder];
  
  /// Default task types
  static List<CustomTaskType> get defaults => [
    const CustomTaskType(id: 'task', label: 'Task', emoji: '', isDefault: true, sortOrder: 0),
    const CustomTaskType(id: 'bug', label: 'Bug', emoji: '', isDefault: true, sortOrder: 1),
    const CustomTaskType(id: 'feature', label: 'Feature', emoji: '', isDefault: true, sortOrder: 2),
    const CustomTaskType(id: 'story', label: 'Story', emoji: '', isDefault: true, sortOrder: 3),
    const CustomTaskType(id: 'epic', label: 'Epic', emoji: '', isDefault: true, sortOrder: 4),
    const CustomTaskType(id: 'improvement', label: 'Improvement', emoji: '', isDefault: true, sortOrder: 5),
    const CustomTaskType(id: 'subtask', label: 'Subtask', emoji: '', isDefault: true, sortOrder: 6),
    const CustomTaskType(id: 'research', label: 'Research', emoji: '', isDefault: true, sortOrder: 7),
  ];
}

/// Custom Priority - User created priorities
@HiveType(typeId: 6)
class CustomPriority extends Equatable {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String label;
  
  @HiveField(2)
  final String emoji;
  
  @HiveField(3)
  final int colorValue;
  
  @HiveField(4)
  final bool isDefault;
  
  @HiveField(5)
  final int sortOrder;
  
  const CustomPriority({
    required this.id,
    required this.label,
    required this.emoji,
    required this.colorValue,
    this.isDefault = false,
    this.sortOrder = 0,
  });
  
  String get displayName => label;
  
  CustomPriority copyWith({
    String? id,
    String? label,
    String? emoji,
    int? colorValue,
    bool? isDefault,
    int? sortOrder,
  }) {
    return CustomPriority(
      id: id ?? this.id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
  
  @override
  List<Object?> get props => [id, label, emoji, colorValue, isDefault, sortOrder];
  
  /// Default priorities
  static List<CustomPriority> get defaults => [
    const CustomPriority(id: 'low', label: 'Low', emoji: '', colorValue: 0xFF2196F3, isDefault: true, sortOrder: 0),
    const CustomPriority(id: 'medium', label: 'Medium', emoji: '', colorValue: 0xFFFF9800, isDefault: true, sortOrder: 1),
    const CustomPriority(id: 'high', label: 'High', emoji: '', colorValue: 0xFFF44336, isDefault: true, sortOrder: 2),
    const CustomPriority(id: 'critical', label: 'Critical', emoji: '', colorValue: 0xFFFF5722, isDefault: true, sortOrder: 3),
  ];
}
