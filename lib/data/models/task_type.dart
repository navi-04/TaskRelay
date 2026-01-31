import 'package:hive/hive.dart';

part 'task_type.g.dart';

/// Task types similar to Jira issue types
@HiveType(typeId: 3)
enum TaskType {
  @HiveField(0)
  task('Task', '📋'),

  @HiveField(1)
  bug('Bug', '🐛'),

  @HiveField(2)
  feature('Feature', '✨'),

  @HiveField(3)
  story('Story', '📖'),

  @HiveField(4)
  epic('Epic', '🎯'),

  @HiveField(5)
  improvement('Improvement', '🔧'),

  @HiveField(6)
  subtask('Subtask', '📝'),

  @HiveField(7)
  research('Research', '🔍');

  const TaskType(this.label, this.emoji);

  final String label;
  final String emoji;

  String get displayName => '$emoji $label';
}
