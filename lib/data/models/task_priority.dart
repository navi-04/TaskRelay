import 'package:hive/hive.dart';
import 'package:flutter/material.dart';

part 'task_priority.g.dart';

/// Task priority levels
@HiveType(typeId: 4)
enum TaskPriority {
  @HiveField(0)
  low('Low', '🔵', Colors.blue),

  @HiveField(1)
  medium('Medium', '🟡', Colors.orange),

  @HiveField(2)
  high('High', '🔴', Colors.red),

  @HiveField(3)
  critical('Critical', '🔥', Colors.deepOrange);

  const TaskPriority(this.label, this.emoji, this.color);

  final String label;
  final String emoji;
  final Color color;

  String get displayName => '$emoji $label';
}
