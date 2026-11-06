import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../platform/permissions_flow.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import '../search/search_screen.dart';
import 'task_card.dart';
import 'task_form.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _quick = TextEditingController();
  final Set<String> _busyIds = {};
  bool _working = false;

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.read(taskActionsProvider).changed();
    ref.invalidate(settingsProvider);
    ref.invalidate(labelsProvider);
    await ref.read(dayViewProvider(ref.read(todayDateProvider)).future).catchError((_) => DayView(date: '', today: '', tasks: const [], top: const [], summary: const DaySummary(planned: 0, done: 0, plannedMin: 0, doneMin: 0)));
  }

  /// Runs one change; failures are shown, never swallowed.
  Future<void> _guard(Future<void> Function() fn, {String? busyId}) async {
    setState(() {
      if (busyId != null) {
        _busyIds.add(busyId);
      } else {
        _working = true;
      }
    });
    try {
      await fn();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          if (busyId != null) {
            _busyIds.remove(busyId);
          } else {
            _working = false;
          }
        });
      }
    }
  }

  Future<void> _openForm({Task? task, required DayView view, SharedText? prefill}) async {
    Labels labels;
    try {
      labels = await ref.read(labelsProvider.future);
    } catch (_) {
      labels = const Labels(types: [], priorities: []);
    }
    if (!mounted) return;
    final saved = await showTaskForm(context, task: task, date: view.date, today: view.today, labels: labels, prefill: prefill);
    // A task with a reminder is pointless if Android won't let it ring: offer to fix the first missing permission.
    if (saved != null && saved.alarmTime != null && mounted) {
      final bridge = ref.read(bridgeProvider);
      final missing = firstMissingPermission(await bridge.permissions());
      if (missing != null && mounted) await fixPermission(context, bridge, missing);
    }
  }

  Future<void> _delete(Task t, DayView v) async {
    final repeating = t.isRepeating;
    final choice = await askChoice(
      context,
      title: 'Delete “${t.title}”?',
      message: repeating ? 'This task repeats. What should be deleted?' : null,
      choices: repeating
          ? [
              (id: 'day:${v.date}', label: 'Just ${fmtDay(v.date)}', destructive: true),
              (id: 'from:${v.date}', label: 'This and all following days', destructive: true),
              (id: 'all', label: 'The whole series', destructive: true),
            ]
          : [(id: 'all', label: 'Delete', destructive: true)],
    );
    if (choice == null || !mounted) return;
    await _guard(busyId: t.id, () async {
      final undo = await ref.read(taskActionsProvider).delete(t, choice);
      if (mounted) showUndo(context, undo);
    });
  }

  Future<void> _star(Task t, DayView v) {
    final next = t.isTop ? v.top.where((id) => id != t.id).toList() : [...v.top, t.id];
    return _guard(busyId: t.id, () => ref.read(taskActionsProvider).setTop(v.date, next));
  }

  Future<void> _editNote(Task t) async {
    final saved = await askText(context, title: 'Note', initial: t.dayNote ?? '', hint: 'How did it go? (optional)', maxLength: 1000, maxLines: 3);
    if (saved == null || !mounted) return;
    await _guard(busyId: t.id, () => ref.read(taskActionsProvider).setNote(t, saved.isEmpty ? null : saved));
  }

  Future<void> _quickAdd(DayView v) async {
    final title = _quick.text.trim();
    if (title.isEmpty) return;
    await _guard(() async {
      await ref.read(taskActionsProvider).create({'id': const Uuid().v4(), 'title': title, 'due_date': v.date, 'duration_min': 30});
      _quick.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(todayDateProvider);
    final view = ref.watch(dayViewProvider(date));
    final labels = ref.watch(labelsProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final stats = ref.watch(statsProvider((from: null, to: null))).valueOrNull;
    final habits = ref.watch(habitsProvider(7)).valueOrNull ?? const <Habit>[];

    final v = view.valueOrNull;

    // The share target and the widget's "+" ask for the add form. They may arrive before the day has loaded
    // (a cold start), so the request waits in the provider until there is a day to add to.
    final request = ref.watch(addRequestProvider);
    if (request != null && v != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(addRequestProvider) == null) return;
        ref.read(addRequestProvider.notifier).state = null;
        _openForm(view: v, prefill: request.prefill);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(v == null ? 'TaskRelay' : (v.isToday ? 'Today' : fmtDay(v.date))),
        actions: [
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()))),
          IconButton(
            tooltip: 'Pick a day',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: v == null
                ? null
                : () async {
                    final picked = await showDatePicker(context: context, initialDate: parseYmd(v.date), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) ref.read(todayDateProvider.notifier).state = ymd(picked) == v.today ? null : ymd(picked);
                  },
          ),
        ],
      ),
      floatingActionButton: v == null ? null : FloatingActionButton.extended(onPressed: () => _openForm(view: v), icon: const Icon(Icons.add), label: const Text('Add task')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            AsyncBody<DayView>(
              value: view,
              onRetry: () => ref.invalidate(dayViewProvider),
              data: (d) => _content(d, labels, settings, stats, habits),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(DayView v, Labels? labels, Settings? settings, StatsView? stats, List<Habit> habits) {
    final t = context.tr;
    final streak = stats?.streak ?? 0;
    final p = v.summary;
    final used = settings == null ? 0 : (settings.byTime ? p.plannedMin : p.planned);
    final limit = settings?.limit ?? 0;
    final over = limit > 0 && used > limit;
    Habit? habitOf(String id) => habits.where((h) => h.taskId == id).firstOrNull;

    Widget row(Task task) => TaskCard(
          key: ValueKey('${task.id}/${v.date}'),
          task: task,
          priority: labels?.priority(task.priorityId),
          habit: habitOf(task.id),
          busy: _busyIds.contains(task.id),
          canStar: v.top.length < 3,
          onToggle: () => _guard(busyId: task.id, () => ref.read(taskActionsProvider).setDone(task, !task.isDone)),
          onStar: () => _star(task, v),
          onMenu: (m) => switch (m) {
            TaskMenu.edit => _openForm(task: task, view: v),
            TaskMenu.note => _editNote(task),
            TaskMenu.delete => _delete(task, v),
          },
        );

    final overdue = v.overdue;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // day navigation
      Row(children: [
        IconButton(tooltip: 'Previous day', icon: const Icon(Icons.chevron_left), onPressed: () => _go(shiftYmd(v.date, -1), v)),
        Expanded(child: Text(fmtDayLong(v.date), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Next day', icon: const Icon(Icons.chevron_right), onPressed: () => _go(shiftYmd(v.date, 1), v)),
      ]),
      if (!v.isToday) Align(alignment: Alignment.center, child: TextButton(onPressed: () => ref.read(todayDateProvider.notifier).state = null, child: const Text('Back to today'))),
      const SizedBox(height: 4),

      SurfaceCard(
        semanticLabel: 'Day summary',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ProgressRing(percent: p.planned == 0 ? 0 : p.done / p.planned * 100, label: '${p.done}/${p.planned}'),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.planned == 0 ? 'Nothing planned' : (p.done == p.planned ? 'All done!' : '${plural(p.planned - p.done, 'task')} to go'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (streak > 0)
                  IconText(Icons.local_fire_department_outlined, '${plural(streak, 'day')} in a row', style: TextStyle(color: t.muted))
                else
                  Text('Finish a day to start a streak', style: TextStyle(color: t.muted)),
              ]),
            ),
          ]),
          if (limit > 0) ...[
            const SizedBox(height: 14),
            _CapacityBar(used: used, limit: limit, over: over),
            const SizedBox(height: 4),
            Text(
              '${settings!.byTime ? '${fmtMinutes(used)} planned of ${fmtMinutes(limit)}' : '$used of $limit tasks planned'}${over ? ' — over your daily limit' : ''}',
              style: TextStyle(fontSize: 12, color: over ? Theme.of(context).colorScheme.onSurface : t.muted, fontWeight: over ? FontWeight.w800 : FontWeight.w400),
            ),
          ],
        ]),
      ),

      // quick add
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _quick,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: 'Add a task for ${v.isToday ? 'today' : fmtDay(v.date)}…', counterText: '', filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
              onSubmitted: (_) => _quickAdd(v),
            ),
          ),
          // explicit colours: the theme-wide icon foreground equals this button's fill, which made the arrow invisible
          IconButton.filled(
            tooltip: 'Add task',
            style: IconButton.styleFrom(backgroundColor: t.accent, foregroundColor: t.accentInk),
            onPressed: _working ? null : () => _quickAdd(v),
            icon: const Icon(Icons.arrow_upward),
          ),
        ]),
      ),

      if (overdue != null && overdue.count > 0)
        SurfaceCard(
          semanticLabel: 'Overdue tasks',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // A Wrap, not a Row: with the title and this button side by side a 360dp phone overflows, and big text far more.
            SizedBox(
              width: double.infinity,
              child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 4, children: [
                Text('Overdue · ${overdue.count}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                OutlinedButton(
                  onPressed: _working ? null : () => _guard(() async {
                    final undo = await ref.read(taskActionsProvider).moveOverdue(overdue.items, v.today);
                    if (mounted) showUndo(context, undo);
                  }),
                  child: Text(overdue.items.length == overdue.count ? 'Move all to today' : 'Move ${overdue.items.length} to today'),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            for (final o in overdue.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(o.title, style: const TextStyle(fontWeight: FontWeight.w600)), Text('was due ${fmtDay(o.dueDate)} · ${fmtMinutes(o.durationMin)}', style: TextStyle(color: t.muted, fontSize: 12))])),
                  IconButton(tooltip: 'Edit ${o.title}', icon: const Icon(Icons.edit_outlined), onPressed: () => _openForm(task: o, view: v)),
                  IconButton(tooltip: 'Delete ${o.title}', icon: const Icon(Icons.close), onPressed: () => _delete(o, v)),
                ]),
              ),
            if (overdue.count > overdue.items.length) Text('Showing the ${overdue.items.length} most recent of ${overdue.count}.', style: TextStyle(color: t.muted, fontSize: 12)),
          ]),
        ),

      if (v.topTasks.isNotEmpty)
        SurfaceCard(semanticLabel: 'Top 3', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionTitle('★ Top 3 for ${v.isToday ? 'today' : fmtDay(v.date)}'), for (final task in v.topTasks) row(task)])),

      SurfaceCard(
        semanticLabel: 'Tasks',
        child: v.tasks.isEmpty
            ? EmptyState(title: v.isToday ? 'A clear day' : 'Nothing planned for this day', message: 'Add a task above to get started.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (v.topTasks.isNotEmpty) const SectionTitle('Other tasks'),
                if (v.otherTasks.isEmpty) Text('Everything is in your Top 3.', style: TextStyle(color: t.muted)) else for (final task in v.otherTasks) row(task),
              ]),
      ),
    ]);
  }

  void _go(String d, DayView v) => ref.read(todayDateProvider.notifier).state = d == v.today ? null : d;
}

/// Planned vs the daily limit. Over the limit the bar is striped, so it is obvious without colour.
class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.used, required this.limit, required this.over});
  final int used;
  final int limit;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Semantics(
      label: 'Planned $used of $limit${over ? ', over the limit' : ''}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 8,
          child: over
              ? CustomPaint(painter: _StripePainter(t.accent, t.track), size: const Size(double.infinity, 8))
              : LinearProgressIndicator(value: (used / limit).clamp(0, 1).toDouble(), minHeight: 8),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.a, this.b);
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    final p = Paint()
      ..color = a
      ..strokeWidth = 5;
    for (double x = -size.height; x < size.width + size.height; x += 10) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.a != a || old.b != b;
}
