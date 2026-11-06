// Plain immutable models that mirror the API's JSON (snake_case). They are parsed against the real fixtures in
// web/test/fixtures by test/models_test.dart, so a change to the API contract fails a test on both sides.

typedef Json = Map<String, dynamic>;

int _int(Object? v) => (v as num).toInt();
String? _str(Object? v) => v as String?;
List<T> _list<T>(Object? v, T Function(Json) f) => ((v as List?) ?? const []).map((e) => f(e as Json)).toList();

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.notes,
    required this.durationMin,
    required this.typeId,
    required this.priorityId,
    required this.dueDate,
    required this.alarmTime,
    required this.reminderKind,
    required this.recur,
    required this.recurUntil,
    required this.recurDays,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedBy,
    required this.date,
    required this.status,
    required this.dayNote,
    required this.completedAt,
    required this.dayUpdatedBy,
    required this.topPosition,
  });

  final String id;
  final String title;
  final String? notes;
  final int durationMin;
  final String? typeId;
  final String? priorityId;
  final String dueDate;

  /// 'HH:mm' (24h, local) or null.
  final String? alarmTime;

  /// 'alarm' (full-screen) or 'notification'.
  final String reminderKind;

  /// 'none' or 'daily' (= repeating: every day, or only on [recurDays]).
  final String recur;
  final String? recurUntil;

  /// 1=Mon..7=Sun, or null for every day.
  final List<int>? recurDays;
  final String createdAt;
  final String updatedAt;

  /// 'app' (the user) or 'ai' (an assistant) - who last changed the task.
  final String updatedBy;

  /// The calendar day this view of the task is for.
  final String date;

  /// 'open' | 'done' | 'skipped' on [date].
  final String status;
  final String? dayNote;
  final String? completedAt;
  final String? dayUpdatedBy;

  /// 1..3 when in that day's Top 3.
  final int? topPosition;

  bool get isDone => status == 'done';
  bool get isRepeating => recur != 'none';
  bool get isTop => topPosition != null;

  /// Did an AI assistant change this (or tick it off) in the last 48 hours? A later edit by the user clears it.
  bool changedByClaude([DateTime? now]) {
    final n = now ?? DateTime.now();
    const window = Duration(hours: 48);
    if (updatedBy == 'ai' && n.difference(DateTime.parse(updatedAt)) < window) return true;
    return dayUpdatedBy == 'ai' && completedAt != null && n.difference(DateTime.parse(completedAt!)) < window;
  }

  factory Task.fromJson(Json j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        notes: _str(j['notes']),
        durationMin: _int(j['duration_min']),
        typeId: _str(j['type_id']),
        priorityId: _str(j['priority_id']),
        dueDate: j['due_date'] as String,
        alarmTime: _str(j['alarm_time']),
        reminderKind: j['reminder_kind'] as String,
        recur: j['recur'] as String,
        recurUntil: _str(j['recur_until']),
        recurDays: (j['recur_days'] as List?)?.map((e) => (e as num).toInt()).toList(),
        createdAt: j['created_at'] as String,
        updatedAt: j['updated_at'] as String,
        updatedBy: j['updated_by'] as String,
        date: j['date'] as String,
        status: j['status'] as String,
        dayNote: _str(j['day_note']),
        completedAt: _str(j['completed_at']),
        dayUpdatedBy: _str(j['day_updated_by']),
        topPosition: j['top_position'] == null ? null : _int(j['top_position']),
      );
}

class DaySummary {
  const DaySummary({required this.planned, required this.done, required this.plannedMin, required this.doneMin});
  final int planned;
  final int done;
  final int plannedMin;
  final int doneMin;

  factory DaySummary.fromJson(Json j) => DaySummary(planned: _int(j['planned']), done: _int(j['done']), plannedMin: _int(j['planned_min']), doneMin: _int(j['done_min']));
}

class Overdue {
  const Overdue({required this.items, required this.count});
  final List<Task> items;

  /// The true total (the list is capped at 50).
  final int count;
}

class DayView {
  const DayView({required this.date, required this.today, required this.tasks, required this.top, required this.summary, this.overdue});
  final String date;

  /// The server's idea of today for this user (their timezone): the single truth for "today".
  final String today;
  final List<Task> tasks;

  /// Ids of that day's Top 3, in order.
  final List<String> top;
  final DaySummary summary;
  final Overdue? overdue;

  bool get isToday => date == today;
  List<Task> get topTasks => (tasks.where((t) => t.isTop).toList()..sort((a, b) => a.topPosition!.compareTo(b.topPosition!)));
  List<Task> get otherTasks => tasks.where((t) => !t.isTop).toList();

  factory DayView.fromJson(Json j) => DayView(
        date: j['date'] as String,
        today: j['today'] as String,
        tasks: _list(j['tasks'], Task.fromJson),
        top: ((j['top'] as List?) ?? const []).cast<String>(),
        summary: DaySummary.fromJson(j['summary'] as Json),
        overdue: j['overdue'] == null
            ? null
            : Overdue(items: _list((j['overdue'] as Json)['items'], Task.fromJson), count: _int((j['overdue'] as Json)['count'])),
      );
}

class Label {
  const Label({required this.id, required this.kind, required this.label, required this.color, required this.sortOrder});
  final String id;
  final String kind;
  final String label;
  final int color;
  final int sortOrder;

  factory Label.fromJson(Json j) => Label(id: j['id'] as String, kind: j['kind'] as String, label: j['label'] as String, color: _int(j['color']), sortOrder: _int(j['sort_order']));
}

class Labels {
  const Labels({required this.types, required this.priorities});
  final List<Label> types;
  final List<Label> priorities;

  Label? priority(String? id) => id == null ? null : priorities.where((p) => p.id == id).firstOrNull;
  Label? type(String? id) => id == null ? null : types.where((p) => p.id == id).firstOrNull;

  factory Labels.fromJson(Json j) => Labels(types: _list(j['types'], Label.fromJson), priorities: _list(j['priorities'], Label.fromJson));
}

class Settings {
  const Settings({
    required this.estimationMode,
    required this.dailyTimeLimitMin,
    required this.dailyCountLimit,
    required this.dailyReminderOn,
    required this.dailyReminderHour,
    required this.dailyReminderMin,
    required this.endOfDayOn,
    required this.endOfDayHour,
    required this.endOfDayMin,
    required this.carryOverAlerts,
  });

  /// 'time' (minutes) or 'count' (number of tasks).
  final String estimationMode;
  final int dailyTimeLimitMin;
  final int dailyCountLimit;
  final bool dailyReminderOn;
  final int dailyReminderHour;
  final int dailyReminderMin;
  final bool endOfDayOn;
  final int endOfDayHour;
  final int endOfDayMin;
  final bool carryOverAlerts;

  bool get byTime => estimationMode == 'time';

  /// The limit that applies in the current mode.
  int get limit => byTime ? dailyTimeLimitMin : dailyCountLimit;

  Settings copyWith({
    String? estimationMode,
    int? dailyTimeLimitMin,
    int? dailyCountLimit,
    bool? dailyReminderOn,
    int? dailyReminderHour,
    int? dailyReminderMin,
    bool? endOfDayOn,
    int? endOfDayHour,
    int? endOfDayMin,
    bool? carryOverAlerts,
  }) =>
      Settings(
        estimationMode: estimationMode ?? this.estimationMode,
        dailyTimeLimitMin: dailyTimeLimitMin ?? this.dailyTimeLimitMin,
        dailyCountLimit: dailyCountLimit ?? this.dailyCountLimit,
        dailyReminderOn: dailyReminderOn ?? this.dailyReminderOn,
        dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
        dailyReminderMin: dailyReminderMin ?? this.dailyReminderMin,
        endOfDayOn: endOfDayOn ?? this.endOfDayOn,
        endOfDayHour: endOfDayHour ?? this.endOfDayHour,
        endOfDayMin: endOfDayMin ?? this.endOfDayMin,
        carryOverAlerts: carryOverAlerts ?? this.carryOverAlerts,
      );

  Json toJson() => {
        'estimation_mode': estimationMode,
        'daily_time_limit_min': dailyTimeLimitMin,
        'daily_count_limit': dailyCountLimit,
        'daily_reminder_on': dailyReminderOn,
        'daily_reminder_hour': dailyReminderHour,
        'daily_reminder_min': dailyReminderMin,
        'end_of_day_on': endOfDayOn,
        'end_of_day_hour': endOfDayHour,
        'end_of_day_min': endOfDayMin,
        'carry_over_alerts': carryOverAlerts,
      };

  /// Only the fields that differ from [saved] (what to send in a PATCH).
  Json diff(Settings saved) {
    final mine = toJson(), theirs = saved.toJson();
    return {for (final k in mine.keys) if (mine[k] != theirs[k]) k: mine[k]};
  }

  factory Settings.fromJson(Json j) => Settings(
        estimationMode: j['estimation_mode'] as String,
        dailyTimeLimitMin: _int(j['daily_time_limit_min']),
        dailyCountLimit: _int(j['daily_count_limit']),
        dailyReminderOn: j['daily_reminder_on'] as bool,
        dailyReminderHour: _int(j['daily_reminder_hour']),
        dailyReminderMin: _int(j['daily_reminder_min']),
        endOfDayOn: j['end_of_day_on'] as bool,
        endOfDayHour: _int(j['end_of_day_hour']),
        endOfDayMin: _int(j['end_of_day_min']),
        carryOverAlerts: j['carry_over_alerts'] as bool,
      );

  @override
  bool operator ==(Object other) => other is Settings && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

class Me {
  const Me({required this.id, required this.email, required this.timezone, required this.aiAccessId, required this.aiAccessEnabled, required this.aiLastUsedAt});
  final String id;
  final String email;
  final String timezone;
  final String aiAccessId;
  final bool aiAccessEnabled;
  final DateTime? aiLastUsedAt;

  factory Me.fromJson(Json j) => Me(
        id: j['id'] as String,
        email: j['email'] as String,
        timezone: j['timezone'] as String,
        aiAccessId: j['ai_access_id'] as String,
        aiAccessEnabled: j['ai_access_enabled'] as bool,
        aiLastUsedAt: j['ai_last_used_at'] == null ? null : DateTime.parse(j['ai_last_used_at'] as String),
      );
}

class DayStat {
  const DayStat({required this.date, required this.planned, required this.done, required this.onTime, required this.plannedMin, required this.doneMin});
  final String date;
  final int planned;
  final int done;
  final int onTime;
  final int plannedMin;
  final int doneMin;

  factory DayStat.fromJson(Json j) => DayStat(date: j['date'] as String, planned: _int(j['planned']), done: _int(j['done']), onTime: _int(j['on_time']), plannedMin: _int(j['planned_min']), doneMin: _int(j['done_min']));
}

class WeekSummary {
  const WeekSummary({required this.planned, required this.done, required this.completionPct, required this.plannedMin, required this.doneMin});
  final int planned;
  final int done;
  final int completionPct;
  final int plannedMin;
  final int doneMin;

  factory WeekSummary.fromJson(Json j) => WeekSummary(planned: _int(j['planned']), done: _int(j['done']), completionPct: _int(j['completion_pct']), plannedMin: _int(j['planned_min']), doneMin: _int(j['done_min']));
}

class StatsView {
  const StatsView({required this.today, required this.from, required this.to, required this.days, required this.streak, required this.week});
  final String today;
  final String from;
  final String to;
  final List<DayStat> days;
  final int streak;
  final WeekSummary week;

  factory StatsView.fromJson(Json j) => StatsView(
        today: j['today'] as String,
        from: j['from'] as String,
        to: j['to'] as String,
        days: _list(j['days'], DayStat.fromJson),
        streak: _int(j['streak']),
        week: WeekSummary.fromJson(j['week'] as Json),
      );
}

class HabitDay {
  const HabitDay(this.date, this.state);

  final String date;

  /// 'done' | 'missed' | 'skipped' | 'pending' | 'none' (not scheduled that day).
  final String state;
}

class Habit {
  const Habit({required this.taskId, required this.title, required this.recurDays, required this.currentStreak, required this.bestStreak, required this.rate30, required this.rate90, required this.last7});
  final String taskId;
  final String title;
  final List<int>? recurDays;
  final int currentStreak;
  final int bestStreak;
  final int? rate30;
  final int? rate90;
  final List<HabitDay> last7;

  factory Habit.fromJson(Json j) => Habit(
        taskId: j['task_id'] as String,
        title: j['title'] as String,
        recurDays: (j['recur_days'] as List?)?.map((e) => (e as num).toInt()).toList(),
        currentStreak: _int(j['current_streak']),
        bestStreak: _int(j['best_streak']),
        rate30: j['rate_30'] == null ? null : _int(j['rate_30']),
        rate90: j['rate_90'] == null ? null : _int(j['rate_90']),
        last7: _list(j['last7'], (d) => HabitDay(d['date'] as String, d['state'] as String)),
      );
}

class ActivityItem {
  const ActivityItem({required this.id, required this.at, required this.kind, required this.taskId, required this.title, required this.date});
  final int id;
  final DateTime at;
  final String kind;
  final String taskId;
  final String title;
  final String? date;

  factory ActivityItem.fromJson(Json j) => ActivityItem(id: _int(j['id']), at: DateTime.parse(j['at'] as String), kind: j['kind'] as String, taskId: j['task_id'] as String, title: j['title'] as String, date: _str(j['date']));
}

class ReviewTotals {
  const ReviewTotals({required this.planned, required this.done, required this.onTime, required this.completionPct, required this.onTimePct, required this.plannedMin, required this.doneMin});
  final int planned;
  final int done;
  final int onTime;
  final int completionPct;
  final int onTimePct;
  final int plannedMin;
  final int doneMin;
}

class Review {
  const Review({
    required this.from,
    required this.to,
    required this.totals,
    required this.days,
    required this.bestHours,
    required this.mostMissed,
    required this.byPriority,
    required this.overdueCount,
    required this.streak,
    required this.top3Done,
    required this.top3Total,
    required this.top3Days,
    required this.wins,
    required this.misses,
    required this.planPrompt,
  });
  final String from;
  final String to;
  final ReviewTotals totals;
  final List<DayStat> days;
  final List<({int hour, int count})> bestHours;
  final List<({String title, int missed, int planned})> mostMissed;
  final List<({String priority, int planned, int done})> byPriority;
  final int overdueCount;
  final int streak;
  final int top3Done;
  final int top3Total;
  final int top3Days;
  final List<String> wins;
  final List<String> misses;
  final String planPrompt;

  factory Review.fromJson(Json j) {
    final t = j['totals'] as Json;
    final top = j['top3'] as Json;
    return Review(
      from: j['from'] as String,
      to: j['to'] as String,
      totals: ReviewTotals(
        planned: _int(t['planned']),
        done: _int(t['done']),
        onTime: _int(t['on_time']),
        completionPct: _int(t['completion_pct']),
        onTimePct: _int(t['on_time_pct']),
        plannedMin: _int(t['planned_min']),
        doneMin: _int(t['done_min']),
      ),
      days: _list(j['days'], DayStat.fromJson),
      bestHours: _list(j['best_hours'], (h) => (hour: _int(h['hour']), count: _int(h['count']))),
      mostMissed: _list(j['most_missed'], (m) => (title: m['title'] as String, missed: _int(m['missed']), planned: _int(m['planned']))),
      byPriority: _list(j['by_priority'], (p) => (priority: p['priority'] as String, planned: _int(p['planned']), done: _int(p['done']))),
      overdueCount: _int(j['overdue_count']),
      streak: _int(j['streak']),
      top3Done: _int(top['done']),
      top3Total: _int(top['total']),
      top3Days: _int(top['days_set']),
      wins: ((j['wins'] as List?) ?? const []).cast<String>(),
      misses: ((j['misses'] as List?) ?? const []).cast<String>(),
      planPrompt: j['plan_prompt'] as String,
    );
  }
}

class SearchPage {
  const SearchPage({required this.items, required this.hasMore});
  final List<Task> items;
  final bool hasMore;

  factory SearchPage.fromJson(Json j) => SearchPage(items: _list(j['items'], Task.fromJson), hasMore: j['has_more'] as bool);
}

// ── the spreadsheet view ─────────────────────────────────────────────────────────────────────────────────────

enum CellState { done, open, skipped }

CellState _cell(Object? v) => switch (v) {
      'done' => CellState.done,
      'skipped' => CellState.skipped,
      _ => CellState.open,
    };

/// A repeating task: it gets its own tick column.
class SheetColumn {
  const SheetColumn({required this.taskId, required this.title, required this.durationMin, required this.alarmTime, required this.recurDays});
  final String taskId;
  final String title;
  final int durationMin;
  final String? alarmTime;

  /// 1=Mon..7=Sun, or null for every day.
  final List<int>? recurDays;

  factory SheetColumn.fromJson(Json j) => SheetColumn(
        taskId: j['task_id'] as String,
        title: j['title'] as String,
        durationMin: _int(j['duration_min']),
        alarmTime: _str(j['alarm_time']),
        recurDays: (j['recur_days'] as List?)?.map((e) => _int(e)).toList(),
      );
}

/// A one-off task on its day.
class SheetTask {
  const SheetTask({required this.id, required this.title, required this.status, required this.durationMin, required this.alarmTime});
  final String id;
  final String title;
  final CellState status;
  final int durationMin;
  final String? alarmTime;

  bool get isDone => status == CellState.done;

  factory SheetTask.fromJson(Json j) => SheetTask(id: j['id'] as String, title: j['title'] as String, status: _cell(j['status']), durationMin: _int(j['duration_min']), alarmTime: _str(j['alarm_time']));
}

class SheetDay {
  const SheetDay({
    required this.date,
    required this.weekday,
    required this.isWeekend,
    required this.isToday,
    required this.cells,
    required this.tasks,
    required this.planned,
    required this.done,
    required this.pct,
    required this.notes,
  });
  final String date;

  /// 1=Mon..7=Sun.
  final int weekday;
  final bool isWeekend;
  final bool isToday;

  /// Task id -> state, for the repeating tasks that occur this day. A missing key means "not scheduled".
  final Map<String, CellState> cells;
  final List<SheetTask> tasks;
  final int planned;
  final int done;
  final int? pct;
  final List<String> notes;

  /// Something planned and not all done.
  bool get isIncomplete => planned > done;

  factory SheetDay.fromJson(Json j) => SheetDay(
        date: j['date'] as String,
        weekday: _int(j['weekday']),
        isWeekend: j['is_weekend'] as bool,
        isToday: j['is_today'] as bool,
        cells: {for (final e in (j['cells'] as Json).entries) e.key: _cell(e.value)},
        tasks: _list(j['tasks'], SheetTask.fromJson),
        planned: _int(j['planned']),
        done: _int(j['done']),
        pct: j['pct'] == null ? null : _int(j['pct']),
        notes: ((j['notes'] as List?) ?? const []).cast<String>(),
      );
}

class SheetView {
  const SheetView({required this.from, required this.to, required this.today, required this.columns, required this.days});
  final String from;
  final String to;
  final String today;
  final List<SheetColumn> columns;
  final List<SheetDay> days;

  factory SheetView.fromJson(Json j) => SheetView(
        from: j['from'] as String,
        to: j['to'] as String,
        today: j['today'] as String,
        columns: _list(j['columns'], SheetColumn.fromJson),
        days: _list(j['days'], SheetDay.fromJson),
      );
}
