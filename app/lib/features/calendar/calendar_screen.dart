import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import '../review/review_screen.dart';

const _badges = [
  (days: 1, icon: Icons.local_fire_department_outlined, title: 'First Flame'),
  (days: 3, icon: Icons.bolt, title: 'Quick Start'),
  (days: 7, icon: Icons.star_outline, title: 'Week Warrior'),
  (days: 14, icon: Icons.star, title: 'Two Weeks'),
  (days: 30, icon: Icons.emoji_events_outlined, title: 'Champion'),
  (days: 100, icon: Icons.diamond_outlined, title: 'Diamond'),
];

/// Calendar + insights: a month grid, the last 7 days, streak achievements and habits.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  String? _month; // first day of the month being shown; null until we know "today"

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(statsProvider((from: null, to: null))); // gives "today" (user's timezone), streak, last 7 days
    final today = overview.valueOrNull?.today;
    final month = _month ?? (today == null ? null : monthStart(today));
    final grid = month == null ? const <GridDay>[] : monthGrid(month);
    final monthStats = (today == null || grid.isEmpty) ? null : ref.watch(statsProvider((from: grid.first.date, to: grid.last.date)));
    final habits = ref.watch(habitsProvider(90));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewScreen())), icon: const Icon(Icons.insights_outlined), label: const Text('Weekly review'))],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(taskActionsProvider).changed(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            AsyncBody<StatsView>(
              value: overview,
              onRetry: () => ref.invalidate(statsProvider),
              data: (o) => _body(o, month!, grid, monthStats, habits),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(StatsView o, String month, List<GridDay> grid, AsyncValue<StatsView>? monthStats, AsyncValue<List<Habit>> habits) {
    final t = context.tr;
    final today = o.today;
    final byDate = {for (final d in monthStats?.valueOrNull?.days ?? const <DayStat>[]) d.date: d};
    final names = shortWeekdays();

    DayKind kindOf(String date) {
      final s = byDate[date];
      return s == null ? DayKind.none : dayKind(planned: s.planned, done: s.done, date: date, today: today);
    }

    final inMonth = grid.where((g) => g.inMonth).map((g) => g.date).toList();
    final kinds = inMonth.map(kindOf).toList();
    int count(DayKind k) => kinds.where((x) => x == k).length;
    var pastPlanned = 0, pastDone = 0;
    for (final d in inMonth) {
      final s = byDate[d];
      if (s != null && d.compareTo(today) <= 0) {
        pastPlanned += s.planned;
        pastDone += s.done;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SurfaceCard(
        semanticLabel: 'Month',
        child: Column(children: [
          Row(children: [
            IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _month = addMonths(month, -1))),
            Expanded(child: Semantics(liveRegion: true, child: Text(fmtMonth(month), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))),
            IconButton(tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _month = addMonths(month, 1))),
          ]),
          if (monthStats?.hasError == true && !monthStats!.isLoading) ErrorBanner(message: friendlyError(monthStats.error!), onRetry: () => ref.invalidate(statsProvider)),
          Row(children: [for (final n in names) Expanded(child: Center(child: Text(n, style: TextStyle(fontSize: 11, color: t.muted, fontWeight: FontWeight.w700))))]),
          const SizedBox(height: 4),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // A fixed shape (aspect ratio) made cells too short for their two text lines on narrow phones and with big text.
            // The height follows the text size instead: two lines + padding + border.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              mainAxisExtent: 2 * _DayCell.lineHeight * MediaQuery.textScalerOf(context).scale(1) + 14,
            ),
            children: [
              for (final g in grid)
                _DayCell(
                  date: g.date,
                  inMonth: g.inMonth,
                  isToday: g.date == today,
                  kind: kindOf(g.date),
                  stat: byDate[g.date],
                  onTap: () {
                    ref.read(todayDateProvider.notifier).state = g.date == today ? null : g.date;
                    ref.read(tabIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [for (final l in const ['✓ all done', '◐ partly done', '✕ missed', '• planned']) Text(l, style: TextStyle(fontSize: 12, color: t.muted))]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${plural(count(DayKind.full), 'day')} complete · ${plural(count(DayKind.partial), 'day')} partial · ${plural(count(DayKind.missed), 'day')} missed${pastPlanned > 0 ? ' · ${(pastDone / pastPlanned * 100).round()}% of tasks done' : ''}',
              style: TextStyle(color: t.muted, fontSize: 13),
            ),
          ),
        ]),
      ),
      SurfaceCard(
        semanticLabel: 'Last 7 days',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Last 7 days'),
          _WeekBars(days: o.days),
          const SizedBox(height: 8),
          Text('${o.week.done} of ${o.week.planned} tasks done (${o.week.completionPct}%)', style: TextStyle(color: t.muted)),
        ]),
      ),
      SurfaceCard(
        semanticLabel: 'Achievements',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Streak: ${plural(o.streak, 'day')}'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in _badges)
              Semantics(
                label: '${b.title}, ${b.days} day streak, ${o.streak >= b.days ? 'unlocked' : 'locked'}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: o.streak >= b.days ? Theme.of(context).colorScheme.onSurface : t.border, width: o.streak >= b.days ? 2 : 1)),
                  child: IconText(o.streak >= b.days ? b.icon : Icons.lock_outline, '${b.title} · ${b.days}', iconSize: 14, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: o.streak >= b.days ? null : t.muted)),
                ),
              ),
          ]),
        ]),
      ),
      SurfaceCard(
        semanticLabel: 'Habits',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Habits'),
          AsyncBody<List<Habit>>(
            value: habits,
            rows: 2,
            onRetry: () => ref.invalidate(habitsProvider),
            data: (list) => list.isEmpty
                ? const EmptyState(title: 'No repeating tasks yet', message: 'Tasks that repeat show their streak here.', icon: Icons.repeat)
                : Column(children: [
                    for (final h in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(h.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${h.currentStreak > 0 ? '${plural(h.currentStreak, 'day')} in a row' : 'No streak right now'} · best ${h.bestStreak}${h.rate90 == null ? '' : ' · ${h.rate90}% over 90 days'}', style: TextStyle(color: t.muted, fontSize: 12)),
                            ]),
                          ),
                          HabitDots(habit: h),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.inMonth, required this.isToday, required this.kind, required this.stat, required this.onTap});
  final String date;
  final bool inMonth;
  final bool isToday;
  final DayKind kind;
  final DayStat? stat;
  final VoidCallback onTap;

  /// One text line in a cell (14sp at height 1.1). The grid sizes cells from this.
  static const lineHeight = 14 * 1.1;

  /// Forces every line to exactly `lineHeight`. The marks (✓ ◐ ✕) come from a fallback font with taller metrics, which would
  /// otherwise make the line taller than the cell the grid sized for it.
  static const _strut = StrutStyle(fontSize: 14, height: 1.1, forceStrutHeight: true);

  static const _marks = {DayKind.none: ('', 'no tasks'), DayKind.planned: ('•', 'planned'), DayKind.full: ('✓', 'all done'), DayKind.partial: ('◐', 'partly done'), DayKind.missed: ('✕', 'missed')};

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final full = kind == DayKind.full;
    final (mark, word) = _marks[kind]!;
    final fg = full ? t.accentInk : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${fmtDay(date)}: ${stat != null && stat!.planned > 0 ? '$word, ${stat!.done} of ${stat!.planned} done' : 'no tasks'}${isToday ? ', today' : ''}',
      child: Opacity(
        opacity: inMonth ? 1 : 0.4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            decoration: BoxDecoration(
              color: full ? t.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: isToday ? Theme.of(context).colorScheme.onSurface : t.border, width: isToday ? 2 : 1),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${int.parse(date.substring(8))}', strutStyle: _strut, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.1, color: fg)),
              Text(mark.isEmpty ? ' ' : mark, strutStyle: _strut, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.1, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Planned (grey) vs done (solid) per day, with the numbers printed so colour is never the only cue.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final max = days.fold<int>(1, (m, d) => d.planned > m ? d.planned : m);
    final names = shortWeekdays();
    return Semantics(
      label: 'Done out of planned: ${days.map((d) => '${names[weekdayIndex(d.date)]} ${d.done} of ${d.planned}').join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 130,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(d.planned == 0 ? '–' : '${d.done}/${d.planned}', style: TextStyle(fontSize: 11, color: t.muted)),
                const SizedBox(height: 4),
                Container(
                  width: 26,
                  height: d.planned == 0 ? 3 : 80 * d.planned / max,
                  decoration: BoxDecoration(color: t.track, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                  alignment: Alignment.bottomCenter,
                  child: d.planned == 0 ? null : Container(height: 80 * d.planned / max * d.done / d.planned, decoration: BoxDecoration(color: t.accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))),
                ),
                const SizedBox(height: 4),
                Text(names[weekdayIndex(d.date)], style: TextStyle(fontSize: 11, color: t.muted)),
              ]),
            ),
        ]),
      ),
    );
  }
}
