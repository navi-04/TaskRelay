import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

enum _Filter { all, incomplete, weekdays }

/// How much bigger than normal the user's text is (1..2). Row and header heights follow it, so big text never overflows a cell.
double _scale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0).toDouble();

// Fixed sizes: the frozen left panel and the scrolling right panel are separate lists that must line up row for row.
const double _rowH = 92;
const double _headH = 84;
const double _dateW = 66;
const double _dayW = 48;
const double _habitW = 84;
const double _tasksW = 250;
const double _numW = 58;
const double _pctW = 66;
const double _notesW = 220;

/// The spreadsheet view: one row per day of a month, a tick column per repeating task, the day's one-off tasks, and the day's
/// Done / Total / %. Tap a tick to complete or reopen that task on that day; tap a date to open the day in Today.
class SheetScreen extends ConsumerStatefulWidget {
  const SheetScreen({super.key});

  @override
  ConsumerState<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends ConsumerState<SheetScreen> {
  late String _month = monthStart(ymd(DateTime.now()));
  _Filter _filter = _Filter.all;

  final _vLeft = ScrollController();
  final _vRight = ScrollController();
  bool _mirroring = false;
  String? _scrolledFor;

  @override
  void initState() {
    super.initState();
    _vLeft.addListener(() => _mirror(_vLeft, _vRight));
    _vRight.addListener(() => _mirror(_vRight, _vLeft));
  }

  @override
  void dispose() {
    _vLeft.dispose();
    _vRight.dispose();
    super.dispose();
  }

  /// Keep the two vertical lists at the same offset (rows have the same height in both).
  void _mirror(ScrollController from, ScrollController to) {
    if (_mirroring || !to.hasClients || !from.hasClients) return;
    _mirroring = true;
    to.jumpTo(from.offset.clamp(0.0, to.position.maxScrollExtent));
    _mirroring = false;
  }

  DateRange get _range =>
      (from: _month, to: shiftYmd(addMonths(_month, 1), -1));

  void _goTo(String month) => setState(() {
    _month = month;
    _scrolledFor = null;
  });

  void _scrollToToday(List<SheetDay> days, String key) {
    if (_scrolledFor == key) return;
    _scrolledFor = key;
    final rowH = _rowH * _scale(context);
    final i = days.indexWhere((d) => d.isToday);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vRight.hasClients) return;
      final target = i < 0 ? 0.0 : math.max(0.0, (i - 1) * rowH);
      _vRight.jumpTo(target.clamp(0.0, _vRight.position.maxScrollExtent));
    });
  }

  Future<void> _toggle(String taskId, String date, bool toDone) async {
    try {
      await ref.read(taskActionsProvider).setCell(taskId, date, toDone);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  void _openDay(String date, String today) {
    ref.read(todayDateProvider.notifier).state = date == today ? null : date;
    ref.read(tabIndexProvider.notifier).state = 0;
  }

  List<SheetDay> _visible(List<SheetDay> days) => switch (_filter) {
    _Filter.all => days,
    _Filter.incomplete => days.where((d) => d.isIncomplete).toList(),
    _Filter.weekdays => days.where((d) => !d.isWeekend).toList(),
  };

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(sheetProvider(_range));
    final thisMonth = monthStart(ymd(DateTime.now()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sheet'),
        actions: [
          PopupMenuButton<_Filter>(
            tooltip: 'Filter days',
            icon: Icon(
              _filter == _Filter.all
                  ? Icons.filter_list
                  : Icons.filter_list_alt,
            ),
            initialValue: _filter,
            onSelected: (f) => setState(() => _filter = f),
            itemBuilder: (_) => [
              for (final f in _Filter.values)
                CheckedPopupMenuItem(
                  value: f,
                  checked: f == _filter,
                  child: Text(switch (f) {
                    _Filter.all => 'All days',
                    _Filter.incomplete => 'Incomplete days',
                    _Filter.weekdays => 'Weekdays only',
                  }),
                ),
            ],
          ),
          TextButton(
            // always enabled: from this month it scrolls back to today's row
            onPressed: () => _goTo(thisMonth),
            child: const Text('Today'),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _goTo(addMonths(_month, -1)),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    fmtMonth(_month),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _goTo(addMonths(_month, 1)),
              ),
            ],
          ),
          Expanded(
            child: value.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: SkeletonRows(rows: 6),
              ),
              error: (e, _) => value.hasValue
                  ? _body(
                      value.requireValue,
                      banner: ErrorBanner(
                        message: 'Couldn’t refresh. ${friendlyError(e)}',
                        onRetry: () => ref.invalidate(sheetProvider),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: ErrorBanner(
                        message: friendlyError(e),
                        onRetry: () => ref.invalidate(sheetProvider),
                      ),
                    ),
              data: (v) => _body(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(SheetView view, {Widget? banner}) {
    final days = _visible(view.days);
    _scrollToToday(days, '$_month/${_filter.name}');
    final empty =
        view.days.every((d) => d.planned == 0) && view.columns.isEmpty;
    return Column(
      children: [
        if (banner != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: banner,
          ),
        if (view.columns.isEmpty && !empty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Tasks that repeat get their own column.',
              style: TextStyle(color: context.tr.muted, fontSize: 12),
            ),
          ),
        Expanded(
          child: empty
              ? const EmptyState(
                  title: 'Nothing in this month yet',
                  message: 'Add a task and it appears here.',
                  icon: Icons.grid_on_outlined,
                )
              : days.isEmpty
              ? const EmptyState(
                  title: 'No days match this filter',
                  message: 'Choose “All days” in the filter menu.',
                  icon: Icons.filter_list,
                )
              : _Grid(
                  view: view,
                  days: days,
                  vLeft: _vLeft,
                  vRight: _vRight,
                  onToggle: _toggle,
                  onOpenDay: (d) => _openDay(d, view.today),
                ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.view,
    required this.days,
    required this.vLeft,
    required this.vRight,
    required this.onToggle,
    required this.onOpenDay,
  });
  final SheetView view;
  final List<SheetDay> days;
  final ScrollController vLeft;
  final ScrollController vRight;
  final void Function(String taskId, String date, bool toDone) onToggle;
  final ValueChanged<String> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final rightW =
        view.columns.length * _habitW + _tasksW + _numW * 2 + _pctW + _notesW;
    final rowH = _rowH * _scale(context);
    final headH = _headH * _scale(context);
    return Row(
      children: [
        // frozen: Date + Day
        SizedBox(
          width: _dateW + _dayW,
          child: Column(
            children: [
              _Header(
                height: headH,
                children: const [
                  _HeadCell(width: _dateW, title: 'Date'),
                  _HeadCell(width: _dayW, title: 'Day'),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  controller: vLeft,
                  itemExtent: rowH,
                  itemCount: days.length,
                  itemBuilder: (_, i) => _RowFrame(
                    day: days[i],
                    today: view.today,
                    child: _DateCells(
                      day: days[i],
                      onTap: () => onOpenDay(days[i].date),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 2,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        Expanded(
          child: Scrollbar(
            notificationPredicate: (n) => n.depth == 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: rightW,
                child: Column(
                  children: [
                    _Header(
                      height: headH,
                      children: [
                        for (final c in view.columns) _HabitHead(column: c),
                        const _HeadCell(width: _tasksW, title: 'Tasks'),
                        const _HeadCell(width: _numW, title: 'Done'),
                        const _HeadCell(width: _numW, title: 'Total'),
                        const _HeadCell(width: _pctW, title: '%'),
                        const _HeadCell(width: _notesW, title: 'Notes'),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: vRight,
                        itemExtent: rowH,
                        itemCount: days.length,
                        itemBuilder: (_, i) {
                          final d = days[i];
                          return _RowFrame(
                            day: d,
                            today: view.today,
                            child: Row(
                              children: [
                                for (final c in view.columns)
                                  _HabitCell(
                                    column: c,
                                    day: d,
                                    onToggle: onToggle,
                                  ),
                                _TasksCell(
                                  day: d,
                                  onToggle: onToggle,
                                  onMore: () => onOpenDay(d.date),
                                ),
                                _TextCell(
                                  width: _numW,
                                  label: 'Done',
                                  text: '${d.done}',
                                  bold: d.isToday,
                                ),
                                _TextCell(
                                  width: _numW,
                                  label: 'Total',
                                  text: '${d.planned}',
                                  bold: d.isToday,
                                ),
                                _PctCell(day: d, today: view.today),
                                _NotesCell(day: d, color: t.muted),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dark band on top. The frozen and the scrolling halves each get one, with the same height.
class _Header extends StatelessWidget {
  const _Header({required this.height, required this.children});
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: context.tr.accent,
    child: Row(children: children),
  );
}

class _HeadCell extends StatelessWidget {
  const _HeadCell({required this.width, required this.title, this.subtitle});
  final double width;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ink = context.tr.accentInk;
    // its own semantics node (a header), so neighbouring cells never merge into it
    return Semantics(
      container: true,
      header: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: ink.withValues(alpha: 0.35))),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.15,
                ),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HabitHead extends StatelessWidget {
  const _HabitHead({required this.column});
  final SheetColumn column;

  @override
  Widget build(BuildContext context) {
    final days = column.recurDays;
    final sub = [
      if (column.alarmTime != null) fmtClock(context, column.alarmTime!),
      if (days != null) repeatLabel(repeating: true, days: days),
    ].join(' · ');
    return _HeadCell(
      width: _habitW,
      title: column.title,
      subtitle: sub.isEmpty ? null : sub,
    );
  }
}

/// A row of the grid: weekends tinted, today bold between two heavy lines. Used by BOTH halves so they line up.
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.day,
    required this.today,
    required this.child,
  });
  final SheetDay day;
  final String today;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: day.isWeekend ? t.input : null,
        border: day.isToday
            ? Border(
                top: BorderSide(color: ink, width: 2),
                bottom: BorderSide(color: ink, width: 2),
              )
            : Border(bottom: BorderSide(color: t.border)),
      ),
      child: child,
    );
  }
}

class _DateCells extends StatelessWidget {
  const _DateCells({required this.day, required this.onTap});
  final SheetDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final weight = day.isToday ? FontWeight.w900 : FontWeight.w600;
    return Semantics(
      container: true,
      button: true,
      label:
          '${fmtDayLong(day.date)}${day.isToday ? ', today' : ''}. Open this day',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: _dateW,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: t.border)),
              ),
              child: Text(
                DateFormat('d MMM').format(parseYmd(day.date)),
                style: TextStyle(fontWeight: weight, fontSize: 13),
              ),
            ),
            Container(
              width: _dayW,
              alignment: Alignment.center,
              child: Text(
                shortWeekdays()[day.weekday - 1],
                style: TextStyle(
                  fontWeight: weight,
                  fontSize: 13,
                  color: day.isWeekend ? t.muted : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitCell extends StatelessWidget {
  const _HabitCell({
    required this.column,
    required this.day,
    required this.onToggle,
  });
  final SheetColumn column;
  final SheetDay day;
  final void Function(String taskId, String date, bool toDone) onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final state = day.cells[column.taskId];
    final frame = BoxDecoration(
      border: Border(right: BorderSide(color: t.border)),
    );
    if (state == null) {
      // not scheduled this day: hatched, and not tappable
      return Container(
        width: _habitW,
        decoration: frame,
        child: SizedBox.expand(
          child: CustomPaint(painter: _HatchPainter(t.border)),
        ),
      );
    }
    final done = state == CellState.done;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      container: true,
      button: true,
      checked: done,
      label:
          '${column.title}, ${fmtDay(day.date)}: ${switch (state) {
            CellState.done => 'done',
            CellState.skipped => 'skipped',
            CellState.open => 'not done',
          }}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onToggle(column.taskId, day.date, !done),
        child: Container(
          width: _habitW,
          alignment: Alignment.center,
          decoration: frame,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? t.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: done ? t.accent : t.fieldBorder,
                width: 2,
              ),
            ),
            child: done
                ? Icon(Icons.check, size: 22, color: t.accentInk)
                : (state == CellState.skipped
                      ? Icon(Icons.remove, size: 22, color: ink)
                      : null),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

class _TasksCell extends StatelessWidget {
  const _TasksCell({
    required this.day,
    required this.onToggle,
    required this.onMore,
  });
  final SheetDay day;
  final void Function(String taskId, String date, bool toDone) onToggle;
  final VoidCallback onMore;

  /// A row has room for three chips, or for two chips and a "+N more" line. More tasks than that: open the day.
  static const _fits = 3;
  static const _whenMore = 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final shown = day.tasks.length <= _fits ? day.tasks : day.tasks.take(_whenMore).toList();
    final more = day.tasks.length - shown.length;
    final s = _scale(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        width: _tasksW,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: t.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final task in shown)
              Semantics(
                container: true,
                button: true,
                checked: task.isDone,
                label:
                    '${task.title}, ${fmtDay(day.date)}: ${task.isDone
                        ? 'done'
                        : task.status == CellState.skipped
                        ? 'skipped'
                        : 'not done'}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onToggle(task.id, day.date, !task.isDone),
                  child: SizedBox(
                    height: 26 * s,
                    child: Row(
                      children: [
                        Icon(
                          task.isDone
                              ? Icons.check_box
                              : (task.status == CellState.skipped
                                    ? Icons.indeterminate_check_box_outlined
                                    : Icons.check_box_outline_blank),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: task.isDone ? t.muted : null,
                              decoration: task.isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (more > 0)
              Semantics(
                button: true,
                label: '$more more tasks on ${fmtDay(day.date)}. Open this day',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onMore,
                  child: SizedBox(
                    height: 22 * s,
                    child: Text(
                      '+$more more',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({
    required this.width,
    required this.label,
    required this.text,
    this.bold = false,
  });
  final double width;
  final String label;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label: $text',
    excludeSemantics: true,
    child: Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: context.tr.border)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

/// Percent done. 100% is inverted (a filled cell) and a past day that is not finished is bold: never colour alone.
class _PctCell extends StatelessWidget {
  const _PctCell({required this.day, required this.today});
  final SheetDay day;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final pct = day.pct;
    final full = pct == 100;
    final lowPast = pct != null && pct < 100 && day.date.compareTo(today) < 0;
    return Semantics(
      container: true,
      label: pct == null ? 'No tasks' : '$pct percent done',
      excludeSemantics: true,
      child: Container(
        width: _pctW,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: full ? t.accent : null,
          border: Border(right: BorderSide(color: t.border)),
        ),
        child: Text(
          pct == null ? '–' : '$pct%',
          style: TextStyle(
            fontWeight: full || lowPast || day.isToday
                ? FontWeight.w900
                : FontWeight.w500,
            fontSize: 13,
            color: full ? t.accentInk : null,
          ),
        ),
      ),
    );
  }
}

class _NotesCell extends StatelessWidget {
  const _NotesCell({required this.day, required this.color});
  final SheetDay day;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: day.notes.isEmpty ? null : 'Notes: ${day.notes.join('. ')}',
    excludeSemantics: true,
    child: Container(
      width: _notesW,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Text(
        day.notes.join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color),
      ),
    ),
  );
}
