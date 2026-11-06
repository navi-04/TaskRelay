import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/time.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../platform/permissions_flow.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// Daily limit (time or task count) and the reminders. Saved explicitly; the server's value is the source of truth.
class RemindersCard extends ConsumerStatefulWidget {
  const RemindersCard({super.key});

  @override
  ConsumerState<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<RemindersCard> {
  Settings? _draft;
  Settings? _saved;
  bool _busy = false;
  late final TextEditingController _minutes = TextEditingController();
  late final TextEditingController _count = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    _count.dispose();
    super.dispose();
  }

  void _adopt(Settings s) {
    _saved = s;
    _draft = s;
    _minutes.text = '${s.dailyTimeLimitMin}';
    _count.text = '${s.dailyCountLimit}';
  }

  bool get _dirty => _draft != null && _saved != null && _draft != _saved;

  bool get _valid {
    final d = _draft;
    return d != null && d.dailyTimeLimitMin >= 15 && d.dailyTimeLimitMin <= 1440 && d.dailyCountLimit >= 1 && d.dailyCountLimit <= 100;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final next = await ref.read(apiProvider).patchSettings(_draft!.diff(_saved!));
      ref.invalidate(settingsProvider);
      ref.read(taskActionsProvider).changed(); // limits change the Today bar; reminders change the native schedule
      if (mounted) {
        setState(() => _adopt(next));
        showMessage(context, 'Saved');
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime(int hour, int minute, void Function(int h, int m) set) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: hour, minute: minute));
    if (picked != null) setState(() => set(picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final async = ref.watch(settingsProvider);
    if (async.hasValue && _draft == null) _adopt(async.requireValue);

    return SurfaceCard(
      semanticLabel: 'Daily limit and reminders',
      child: _draft == null
          ? AsyncBody<Settings>(value: async, rows: 3, onRetry: () => ref.invalidate(settingsProvider), data: (_) => const SizedBox())
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionTitle('Daily limit & reminders'),
              Text('Measure my day by', style: TextStyle(color: t.muted, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'time', icon: Icon(Icons.schedule), label: Text('Time')), ButtonSegment(value: 'count', icon: Icon(Icons.format_list_numbered), label: Text('Tasks'))],
                selected: {_draft!.estimationMode},
                onSelectionChanged: (s) => setState(() => _draft = _draft!.copyWith(estimationMode: s.first)),
              ),
              const SizedBox(height: 12),
              if (_draft!.byTime)
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Daily time limit (minutes, 15–1440)', errorText: (_draft!.dailyTimeLimitMin < 15 || _draft!.dailyTimeLimitMin > 1440) ? 'Enter 15 to 1440' : null),
                  onChanged: (v) => setState(() => _draft = _draft!.copyWith(dailyTimeLimitMin: int.tryParse(v) ?? 0)),
                )
              else
                TextField(
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Daily task limit (1–100)', errorText: (_draft!.dailyCountLimit < 1 || _draft!.dailyCountLimit > 100) ? 'Enter 1 to 100' : null),
                  onChanged: (v) => setState(() => _draft = _draft!.copyWith(dailyCountLimit: int.tryParse(v) ?? 0)),
                ),
              const SizedBox(height: 16),
              Text('Reminders on this phone', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Morning reminder with my Top 3'),
                value: _draft!.dailyReminderOn,
                onChanged: (v) => setState(() => _draft = _draft!.copyWith(dailyReminderOn: v)),
              ),
              if (_draft!.dailyReminderOn)
                _TimeRow(label: 'Time', hour: _draft!.dailyReminderHour, minute: _draft!.dailyReminderMin, onTap: () => _pickTime(_draft!.dailyReminderHour, _draft!.dailyReminderMin, (h, m) => _draft = _draft!.copyWith(dailyReminderHour: h, dailyReminderMin: m))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End-of-day summary'),
                value: _draft!.endOfDayOn,
                onChanged: (v) => setState(() => _draft = _draft!.copyWith(endOfDayOn: v)),
              ),
              if (_draft!.endOfDayOn) _TimeRow(label: 'Time', hour: _draft!.endOfDayHour, minute: _draft!.endOfDayMin, onTap: () => _pickTime(_draft!.endOfDayHour, _draft!.endOfDayMin, (h, m) => _draft = _draft!.copyWith(endOfDayHour: h, endOfDayMin: m))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mention overdue tasks in the morning'),
                value: _draft!.carryOverAlerts,
                onChanged: (v) => setState(() => _draft = _draft!.copyWith(carryOverAlerts: v)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton(onPressed: _dirty && _valid && !_busy ? _save : null, child: Text(_busy ? 'Saving…' : 'Save')),
                if (_dirty) TextButton(onPressed: () => setState(() => _adopt(_saved!)), child: const Text('Discard')),
              ]),
            ]),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.hour, required this.minute, required this.onTap});
  final String label;
  final int hour;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: onTap, icon: const Icon(Icons.schedule, size: 18), label: Text('$label: ${TimeOfDay(hour: hour, minute: minute).format(context)}')),
      );
}

/// Rename, add and delete task types and priorities. Deleting one detaches it from tasks; the last of a kind stays.
class LabelsCard extends ConsumerStatefulWidget {
  const LabelsCard({super.key});

  @override
  ConsumerState<LabelsCard> createState() => _LabelsCardState();
}

class _LabelsCardState extends ConsumerState<LabelsCard> {
  final _name = TextEditingController();
  String _kind = 'priority';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      ref.invalidate(labelsProvider); // show what the server really has
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Label l) async {
    final ctl = TextEditingController(text: l.label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename “${l.label}”'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 40),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Save'))],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty || name == l.label) return;
    await _act(() => ref.read(apiProvider).renameLabel(l.id, name).then((_) {}));
  }

  Future<void> _delete(Label l) async {
    final choice = await askChoice(context, title: 'Delete “${l.label}”?', message: 'Tasks that use it keep working; they just lose this label.', choices: [(id: 'yes', label: 'Delete', destructive: true)]);
    if (choice == null) return;
    await _act(() => ref.read(apiProvider).deleteLabel(l.id));
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await _act(() async {
      await ref.read(apiProvider).createLabel(_kind, name);
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = ref.watch(labelsProvider);
    Widget group(String title, List<Label> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(title, style: TextStyle(color: context.tr.muted, fontWeight: FontWeight.w700, fontSize: 13))),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final l in items)
              InputChip(label: Text(l.label), onPressed: _busy ? null : () => _rename(l), onDeleted: _busy ? null : () => _delete(l), deleteButtonTooltipMessage: 'Delete ${l.label}', tooltip: 'Rename ${l.label}'),
          ]),
        ]);

    return SurfaceCard(
      semanticLabel: 'Types and priorities',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Types & priorities'),
        AsyncBody<Labels>(
          value: labels,
          rows: 2,
          onRetry: () => ref.invalidate(labelsProvider),
          data: (l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [group('Priorities', l.priorities), group('Types', l.types)]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          DropdownButton<String>(value: _kind, underline: const SizedBox(), items: const [DropdownMenuItem(value: 'priority', child: Text('Priority')), DropdownMenuItem(value: 'type', child: Text('Type'))], onChanged: (v) => setState(() => _kind = v!)),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(hintText: 'New name', counterText: ''), onSubmitted: (_) => _add())),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _add, child: const Text('Add')),
        ]),
      ]),
    );
  }
}

/// Are my alarms armed? Last sync, how far ahead they are armed, the next one, and each permission with a fix button.
class AlarmHealthCard extends ConsumerStatefulWidget {
  const AlarmHealthCard({super.key});

  @override
  ConsumerState<AlarmHealthCard> createState() => _AlarmHealthCardState();
}

class _AlarmHealthCardState extends ConsumerState<AlarmHealthCard> with WidgetsBindingObserver {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from an Android settings screen: re-read the permissions.
    if (state == AppLifecycleState.resumed) ref.invalidate(syncStatusProvider);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final r = await ref.read(bridgeProvider).syncNow();
    ref.invalidate(syncStatusProvider);
    if (!mounted) return;
    setState(() => _syncing = false);
    showMessage(context, r.ok ? (r.notModified ? 'Already up to date' : 'Synced') : (r.errorCode == 'network' ? 'No connection. Your armed alarms still ring.' : 'Could not sync (${r.errorCode ?? 'error'})'));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final status = ref.watch(syncStatusProvider);
    return SurfaceCard(
      semanticLabel: 'Alarm health',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Alarms on this phone'),
        AsyncBody<SyncStatus>(
          value: status,
          rows: 2,
          onRetry: () => ref.invalidate(syncStatusProvider),
          data: (s) {
            final st = s;
            final last = st.lastSyncMs == null ? 'never' : ago(DateTime.fromMillisecondsSinceEpoch(st.lastSyncMs!));
            final next = st.nextAlarmMs == null ? 'none' : fmtDay(ymd(DateTime.fromMillisecondsSinceEpoch(st.nextAlarmMs!)));
            Widget perm(String key, bool ok) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(ok ? '✓' : '⚠', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  title: Text(permissionTitle(key)),
                  trailing: ok ? null : OutlinedButton(onPressed: () async { await fixPermission(context, ref.read(bridgeProvider), key); ref.invalidate(syncStatusProvider); }, child: const Text('Allow')),
                );
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Last synced $last · ${plural(st.armedCount, 'alarm')} armed${st.armedThrough == null ? '' : ' through ${fmtDay(st.armedThrough!)}'} · next: $next', style: TextStyle(color: t.muted)),
              if (st.lastError != null && st.lastErrorCode != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Last problem: ${st.lastErrorCode}', style: const TextStyle(fontWeight: FontWeight.w700))),
              const SizedBox(height: 8),
              perm('notifications', st.notificationsAllowed),
              perm('exactAlarm', st.exactAlarmAllowed),
              perm('fullScreenIntent', st.fullScreenIntentAllowed),
              const SizedBox(height: 4),
              Text('Alarms you already have ring even with no connection. Changes made on the web or by Claude reach this phone when the app syncs (every ~45 minutes in the background, and whenever you open it). Some phones delay background work: if alarms ever seem stale, tap “Sync now”.', style: TextStyle(color: t.muted, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _syncing ? null : _syncNow, icon: const Icon(Icons.sync), label: Text(_syncing ? 'Syncing…' : 'Sync now')),
            ]);
          },
        ),
      ]),
    );
  }
}
