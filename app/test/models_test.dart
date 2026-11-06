import 'package:flutter_test/flutter_test.dart';
import 'package:taskrelay/data/models.dart';
import 'package:taskrelay/platform/platform_bridge.dart';

import 'support.dart';

// These parse the files the SERVER generated from its real code (web/test/fixtures), so if the API contract changes
// the server test fails first, and if it changes without the app following, these fail here.
void main() {
  test('day view: tasks, Top 3 ordering, summary, overdue', () {
    final v = DayView.fromJson(fixture('day-view') as Json);
    expect([v.date, v.today, v.isToday], ['2026-11-06', '2026-11-06', true]);
    expect(v.tasks.length, greaterThanOrEqualTo(3));
    expect(v.top, ['fx-task-standup', 'fx-task-gym']);
    expect(v.topTasks.map((t) => t.id), ['fx-task-standup', 'fx-task-gym']);
    expect(v.otherTasks.any((t) => t.isTop), isFalse);
    expect(v.overdue!.count, 1);
    expect(v.overdue!.items.single.title, 'Renew passport');

    final standup = v.tasks.firstWhere((t) => t.id == 'fx-task-standup');
    expect([standup.isDone, standup.alarmTime, standup.reminderKind, standup.dayNote], [true, '09:30', 'alarm', 'Short one']);
    final gym = v.tasks.firstWhere((t) => t.id == 'fx-task-gym');
    expect([gym.isRepeating, gym.recurDays, gym.reminderKind, gym.topPosition], [true, [1, 3, 5], 'notification', 2]);
    expect(v.summary.planned, v.tasks.length);
  });

  test('labels, settings and stats', () {
    final labels = Labels.fromJson(fixture('labels') as Json);
    expect([labels.types.length, labels.priorities.map((p) => p.label).toList()], [8, ['Low', 'Medium', 'High', 'Critical']]);
    expect(labels.priority('label-priority-3')?.label, 'High');
    expect(labels.priority(null), isNull);

    final s = Settings.fromJson(fixture('settings') as Json);
    expect([s.estimationMode, s.byTime, s.limit, s.dailyReminderOn, s.endOfDayOn], ['time', true, 480, true, false]);

    final st = StatsView.fromJson(fixture('stats') as Json);
    expect(st.days.length, 7);
    expect(st.days.first.date, '2026-10-31');
    expect(st.week.planned, greaterThan(0));
  });

  test('settings: copyWith, equality and a diff that contains only what changed', () {
    final a = Settings.fromJson(fixture('settings') as Json);
    final b = a.copyWith(dailyTimeLimitMin: 600, endOfDayOn: true);
    expect(a == b, isFalse);
    expect(a == a.copyWith(), isTrue);
    expect(b.diff(a), {'daily_time_limit_min': 600, 'end_of_day_on': true});
    expect(a.diff(a), isEmpty);
  });

  test('habits, review, activity and search', () {
    final habits = (fixture('habits')['habits'] as List).map((h) => Habit.fromJson(h as Json)).toList();
    expect(habits.length, 2);
    expect(habits.every((h) => h.last7.length == 7), isTrue);
    expect(habits.map((h) => h.title), containsAll(['Gym', 'Meditate']));
    expect(habits.firstWhere((h) => h.title == 'Gym').recurDays, [1, 3, 5]);

    final r = Review.fromJson(fixture('review') as Json);
    expect(r.totals.planned, greaterThan(5));
    expect(r.days.length, 7);
    expect(r.planPrompt, contains('TaskRelay'));
    expect(r.wins, isNotEmpty);

    final a = (fixture('activity')['items'] as List).map((i) => ActivityItem.fromJson(i as Json)).toList();
    expect(a.map((i) => i.kind), ['updated', 'created']);

    final page = SearchPage.fromJson(fixture('search') as Json);
    expect(page.items.single.title, 'Write quarterly report');
    expect(page.hasMore, isFalse);
  });

  test('"changed by Claude" shows for 48 hours and is cleared by an edit in the app', () {
    final base = (fixture('day-view')['tasks'] as List).first as Json;
    Task make({String updatedBy = 'ai', String updatedAt = '2026-11-06T12:00:00.000Z', String? dayBy, String? completedAt}) =>
        Task.fromJson({...base, 'updated_by': updatedBy, 'updated_at': updatedAt, 'day_updated_by': dayBy, 'completed_at': completedAt});
    final now = DateTime.parse('2026-11-07T12:00:00Z');
    expect(make().changedByClaude(now), isTrue);
    expect(make(updatedAt: '2026-11-04T12:00:00.000Z').changedByClaude(now), isFalse); // older than 48 h
    expect(make(updatedBy: 'app').changedByClaude(now), isFalse); // the user edited it since
    expect(make(updatedBy: 'app', dayBy: 'ai', completedAt: '2026-11-07T08:00:00.000Z').changedByClaude(now), isTrue); // Claude ticked it
  });

  group('shared text becomes a task draft', () {
    test('uses the subject as the title and puts the rest in notes', () {
      const s = SharedText(subject: 'Great article', text: 'https://example.com/post\nsome more text');
      expect(s.title, 'Great article');
      expect(s.notes, contains('https://example.com/post'));
    });

    test('with no subject, the first non-empty line is the title', () {
      const s = SharedText(text: '\n\n  Buy milk  \nand eggs');
      expect(s.title, 'Buy milk');
      expect(s.notes, 'and eggs');
    });

    test('caps an enormous title at 200 characters and notes at 4000', () {
      final s = SharedText(text: 'x' * 500);
      expect(s.title.length, 200);
      final big = SharedText(subject: 'S', text: 'y' * 10000);
      expect(big.notes.length, 4000);
    });

    test('empty shares are empty', () {
      expect(const SharedText().title, '');
      expect(const SharedText(text: '   ').title, '');
    });
  });
}
