// Basic smoke test for TaskRelay app
//
// The full app requires Hive initialization, so this test only verifies
// that core model classes can be instantiated correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:sampleapp/data/models/task_entity.dart';
import 'package:sampleapp/data/models/task_type.dart';
import 'package:sampleapp/data/models/task_priority.dart';

void main() {
  group('TaskEntity', () {
    test('create factory produces a valid task', () {
      final task = TaskEntity.create(
        id: 'test-1',
        title: 'Test Task',
        durationMinutes: 30,
        date: '2025-01-01',
      );

      expect(task.id, 'test-1');
      expect(task.title, 'Test Task');
      expect(task.durationMinutes, 30);
      expect(task.isCompleted, false);
      expect(task.completedAt, isNull);
      expect(task.taskType, TaskType.task);
      expect(task.priority, TaskPriority.medium);
    });

    test('markCompleted sets isCompleted and completedAt', () {
      final task = TaskEntity.create(
        id: 'test-2',
        title: 'Complete Me',
        durationMinutes: 15,
        date: '2025-01-01',
      );

      final completed = task.markCompleted();
      expect(completed.isCompleted, true);
      expect(completed.completedAt, isNotNull);
    });

    test('markIncomplete clears completedAt (sentinel pattern)', () {
      final task = TaskEntity.create(
        id: 'test-3',
        title: 'Toggle Me',
        durationMinutes: 20,
        date: '2025-01-01',
      );

      final completed = task.markCompleted();
      expect(completed.completedAt, isNotNull);

      final incomplete = completed.markIncomplete();
      expect(incomplete.isCompleted, false);
      expect(incomplete.completedAt, isNull);
    });

    test('copyWith can clear nullable fields', () {
      final task = TaskEntity.create(
        id: 'test-4',
        title: 'Nullable Test',
        description: 'Has description',
        durationMinutes: 10,
        date: '2025-01-01',
        notes: 'Has notes',
      );

      final cleared = task.copyWith(description: null, notes: null);
      expect(cleared.description, isNull);
      expect(cleared.notes, isNull);
      // Non-cleared fields remain
      expect(cleared.title, 'Nullable Test');
      expect(cleared.durationMinutes, 10);
    });

    test('formattedDuration formats correctly', () {
      final taskMinutes = TaskEntity.create(
        id: 'fmt-1', title: 'Minutes', durationMinutes: 45, date: '2025-01-01',
      );
      expect(taskMinutes.formattedDuration, '45m');

      final taskHours = TaskEntity.create(
        id: 'fmt-2', title: 'Hours', durationMinutes: 120, date: '2025-01-01',
      );
      expect(taskHours.formattedDuration, '2h');

      final taskMixed = TaskEntity.create(
        id: 'fmt-3', title: 'Mixed', durationMinutes: 90, date: '2025-01-01',
      );
      expect(taskMixed.formattedDuration, '1h 30m');
    });
  });

  group('TaskPriority', () {
    test('all priorities have valid labels', () {
      for (final priority in TaskPriority.values) {
        expect(priority.label.isNotEmpty, true,
            reason: '${priority.name} should have a non-empty label');
      }
    });
  });
}
