import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../shared/widgets.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../platform/platform_bridge.dart';
import '../../state/providers.dart';

/// Opens the one task form (add and edit). Resolves with the saved task, or null if closed.
Future<Task?> showTaskForm(
  BuildContext context, {
  Task? task,
  required String date,
  required String today,
  required Labels labels,
  SharedText? prefill,
}) {
  return showModalBottomSheet<Task>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TaskFormSheet(task: task, date: date, today: today, labels: labels, prefill: prefill),
  );
}

enum _Repeat { none, daily, days }

const _durations = [15, 30, 45, 60, 90, 120];

class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({super.key, this.task, required this.date, required this.today, required this.labels, this.prefill});
  final Task? task;
  final String date;
  final String today;
  final Labels labels;
  final SharedText? prefill;

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  // Controllers live in State and are disposed in State.dispose (never right after the sheet's future completes).
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _minutes;

  /// Chosen once per open, so retrying a timed-out "create" can never make a duplicate.
  final String _newId = const Uuid().v4();

  String? _priorityId;
  String? _typeId;
  late String _due;
  TimeOfDay? _alarm;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String _kind = 'alarm';
  _Repeat _repeat = _Repeat.none;
  final Set<int> _days = {};
  String? _until;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final p = widget.prefill;
    _title = TextEditingController(text: t?.title ?? p?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? p?.notes ?? '');
    _minutes = TextEditingController(text: '${t?.durationMin ?? 30}');
    _priorityId = t?.priorityId;
    _typeId = t?.typeId;
    _due = t?.dueDate ?? widget.date;
    _alarm = t?.alarmTime == null ? null : fromHhmm(t!.alarmTime!);
    _start = t?.startTime == null ? null : fromHhmm(t!.startTime!);
    _end = t?.endTime == null ? null : fromHhmm(t!.endTime!);
    _kind = t?.reminderKind ?? 'alarm';
    if (t != null && t.isRepeating) {
      _repeat = t.recurDays == null ? _Repeat.daily : _Repeat.days;
      _days.addAll(t.recurDays ?? const []);
      _until = t.recurUntil;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _mins {
    final n = int.tryParse(_minutes.text.trim());
    return n != null && n >= 1 && n <= 1440 ? n : null;
  }

  static int _minute(TimeOfDay t) => t.hour * 60 + t.minute;

  /// A block never crosses midnight: with both times set the end must come after the start.
  bool get _timesOk => _start == null || _end == null || _minute(_end!) > _minute(_start!);

  /// With a valid start AND end the task takes exactly that long (the server derives it too); otherwise the typed estimate stands.
  int? get _span => _start != null && _end != null && _timesOk ? _minute(_end!) - _minute(_start!) : null;
  int? get _duration => _span ?? _mins;

  bool get _titleOk => _title.text.trim().isNotEmpty && _title.text.length <= 200;
  bool get _daysOk => _repeat != _Repeat.days || _days.isNotEmpty;
  bool get _untilOk => _until == null || _until!.compareTo(_due) >= 0;
  bool get _valid => _titleOk && _timesOk && _duration != null && _daysOk && _untilOk && _notes.text.length <= 4000;

  bool get _wontRingToday {
    final a = _alarm;
    if (a == null || _due != widget.today || _repeat != _Repeat.none) return false;
    final now = TimeOfDay.now();
    return a.hour * 60 + a.minute <= now.hour * 60 + now.minute;
  }

  Future<void> _pickDate(String? initial, ValueChanged<String> set) async {
    final base = initial == null ? parseYmd(_due) : parseYmd(initial);
    final picked = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => set(ymd(picked)));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _alarm ?? const TimeOfDay(hour: 9, minute: 0));
    if (picked != null) setState(() => _alarm = picked);
  }

  Future<void> _pickBlock({required bool start}) async {
    final current = start ? _start : _end;
    final fallback = start ? const TimeOfDay(hour: 9, minute: 0) : (_start == null ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay(hour: (_start!.hour + 1) % 24, minute: _start!.minute));
    final picked = await showTimePicker(context: context, initialTime: current ?? fallback, helpText: start ? 'Start time' : 'End time');
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      // Clearing a side later keeps this length, as the server does.
      if (_span != null) _minutes.text = '$_span';
    });
  }

  Future<void> _save() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    final repeating = _repeat != _Repeat.none;
    final fields = <String, dynamic>{
      'title': _title.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text,
      'duration_min': _duration,
      'type_id': _typeId,
      'priority_id': _priorityId,
      'due_date': _due,
      'alarm_time': _alarm == null ? null : toHhmm(_alarm!),
      'start_time': _start == null ? null : toHhmm(_start!),
      'end_time': _end == null ? null : toHhmm(_end!),
      'reminder_kind': _kind,
      'recur': repeating ? 'daily' : 'none',
      'recur_days': _repeat == _Repeat.days ? (_days.toList()..sort()) : null,
      'recur_until': repeating ? _until : null,
    };
    try {
      final actions = ref.read(taskActionsProvider);
      final saved = widget.task == null ? await actions.create({'id': _newId, ...fields}) : await actions.update(widget.task!.id, fields);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      // Stay open: nothing is lost and nothing pretends to have worked.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _fieldErrors = {for (final i in e.issues) i.path: i.message};
        _error = e.issues.isEmpty ? friendlyError(e) : 'Please fix the highlighted fields.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final names = shortWeekdays();
    final editing = widget.task != null;
    final first = _repeat == _Repeat.days && _days.isNotEmpty ? _firstMatch() : null;

    return PopScope(
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(editing ? 'Edit task' : 'New task', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (editing && widget.task!.isRepeating)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('This task repeats: changes apply to every day of the series.', style: TextStyle(color: t.muted))),
            const SizedBox(height: 12),
            if (_error != null) _Banner(_error!),
            TextField(
              controller: _title,
              autofocus: !editing,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Title', errorText: _fieldErrors['title']),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            _Label(_repeat == _Repeat.none ? 'Day' : 'Starts'),
            OutlinedButton.icon(onPressed: () => _pickDate(null, (d) => _due = d), icon: const Icon(Icons.event), label: Text(fmtDayLong(_due))),
            if (_fieldErrors['due_date'] != null) _Err(_fieldErrors['due_date']!),
            const SizedBox(height: 12),
            const _Label('Start and end time (optional)'),
            ClockRow(icon: Icons.play_arrow_outlined, label: 'Start time', value: _start, onPick: () => _pickBlock(start: true), onClear: () => setState(() => _start = null)),
            const SizedBox(height: 6),
            ClockRow(icon: Icons.stop_outlined, label: 'End time', value: _end, onPick: () => _pickBlock(start: false), onClear: () => setState(() => _end = null)),
            if (!_timesOk) const _Err('End time must be after the start time.'),
            if (_fieldErrors['start_time'] != null) _Err(_fieldErrors['start_time']!),
            if (_fieldErrors['end_time'] != null) _Err(_fieldErrors['end_time']!),
            if (_span != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Takes ${fmtMinutes(_span!)}, from the start and end time.', style: TextStyle(color: t.muted))),
            const SizedBox(height: 12),
            if (_span == null) ...[
              const _Label('Time needed (minutes)'),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final d in _durations)
                  ChoiceChip(label: Text('$d'), labelStyle: chipLabel(context, selected: _mins == d), selected: _mins == d, onSelected: (_) => setState(() => _minutes.text = '$d')),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Minutes (1–1440)', errorText: _mins == null ? 'Enter a whole number from 1 to 1440' : _fieldErrors['duration_min']),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            const _Label('Priority'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(label: const Text('None'), labelStyle: chipLabel(context, selected: _priorityId == null), selected: _priorityId == null, onSelected: (_) => setState(() => _priorityId = null)),
              for (final p in widget.labels.priorities) ChoiceChip(label: Text(p.label), labelStyle: chipLabel(context, selected: _priorityId == p.id), selected: _priorityId == p.id, onSelected: (_) => setState(() => _priorityId = p.id)),
            ]),
            const SizedBox(height: 12),
            const _Label('Type'),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(label: const Text('None'), labelStyle: chipLabel(context, selected: _typeId == null), selected: _typeId == null, onSelected: (_) => setState(() => _typeId = null)),
              for (final p in widget.labels.types) ChoiceChip(label: Text(p.label), labelStyle: chipLabel(context, selected: _typeId == p.id), selected: _typeId == p.id, onSelected: (_) => setState(() => _typeId = p.id)),
            ]),
            const SizedBox(height: 12),
            const _Label('Reminder'),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.alarm), label: Text(_alarm == null ? 'Add a time' : _alarm!.format(context)))),
              if (_alarm != null) IconButton(tooltip: 'Remove reminder', icon: const Icon(Icons.close), onPressed: () => setState(() => _alarm = null)),
            ]),
            if (_start != null && _alarm != _start) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _alarm = _start), child: const Text('Remind me at the start time'))),
            if (_alarm != null) ...[
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'alarm', icon: Icon(Icons.alarm), label: Text('Alarm')), ButtonSegment(value: 'notification', icon: Icon(Icons.notifications_none), label: Text('Notification'))],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ],
            if (_wontRingToday) const _Err('That time has already passed today, so it won’t ring today.'),
            if (_fieldErrors['alarm_time'] != null) _Err(_fieldErrors['alarm_time']!),
            const SizedBox(height: 12),
            const _Label('Repeat'),
            SegmentedButton<_Repeat>(
              segments: const [ButtonSegment(value: _Repeat.none, label: Text('Once')), ButtonSegment(value: _Repeat.daily, label: Text('Every day')), ButtonSegment(value: _Repeat.days, label: Text('Choose days'))],
              selected: {_repeat},
              onSelectionChanged: (s) => setState(() {
                _repeat = s.first;
                if (_repeat == _Repeat.days && _days.isEmpty) _days.add(weekdayIndex(_due) + 1);
              }),
            ),
            if (_repeat == _Repeat.days) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(names[i]),
                    labelStyle: chipLabel(context, selected: _days.contains(i + 1)),
                    selected: _days.contains(i + 1),
                    onSelected: (on) => setState(() => on ? _days.add(i + 1) : _days.remove(i + 1)),
                  ),
              ]),
              // a Wrap: two buttons side by side overflow a small phone at the largest text size
              Wrap(children: [
                TextButton(onPressed: () => setState(() => _days..clear()..addAll([1, 2, 3, 4, 5])), child: const Text('Weekdays')),
                TextButton(onPressed: () => setState(() => _days..clear()..addAll([6, 7])), child: const Text('Weekends')),
              ]),
              if (!_daysOk) const _Err('Pick at least one day.'),
              if (first != null && first != _due) Text('Starts ${fmtDay(first)} (the first chosen day on or after ${fmtDay(_due)}).', style: TextStyle(color: t.muted)),
            ],
            if (_repeat != _Repeat.none) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(_until ?? _due, (d) => _until = d), icon: const Icon(Icons.event_busy), label: Text(_until == null ? 'Never ends' : 'Ends ${fmtDay(_until!)}'))),
                if (_until != null) IconButton(tooltip: 'Remove end date', icon: const Icon(Icons.close), onPressed: () => setState(() => _until = null)),
              ]),
              if (!_untilOk) const _Err('The end date can’t be before the start.'),
              if (_fieldErrors['recur_until'] != null) _Err(_fieldErrors['recur_until']!),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 4000,
              decoration: InputDecoration(labelText: 'Notes (optional)', errorText: _fieldErrors['notes']),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _valid && !_busy ? _save : null,
                  child: _busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.accentInk)) : Text(editing ? 'Save' : 'Add task'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// The first chosen weekday on or after the start date (a series may start on a day that is not chosen).
  String? _firstMatch() {
    for (var i = 0; i < 7; i++) {
      final d = shiftYmd(_due, i);
      if (_days.contains(weekdayIndex(d) + 1)) return d;
    }
    return null;
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: TextStyle(color: context.tr.muted, fontWeight: FontWeight.w600, fontSize: 13)));
}

class _Err extends StatelessWidget {
  const _Err(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 4), child: IconText(Icons.warning_amber_outlined, text, iconSize: 14, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)));
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 6), top: BorderSide(color: context.tr.fieldBorder), right: BorderSide(color: context.tr.fieldBorder), bottom: BorderSide(color: context.tr.fieldBorder))),
        child: Semantics(liveRegion: true, child: IconText(Icons.warning_amber_outlined, text, style: const TextStyle(fontWeight: FontWeight.w700))),
      );
}
