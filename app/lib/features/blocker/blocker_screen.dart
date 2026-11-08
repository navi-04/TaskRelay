import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../data/models.dart';
import '../../platform/platform_bridge.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';
import 'app_picker_screen.dart';
import 'blocker_logic.dart';

/// Block distracting apps: pick the apps, then how they are held back. The phone enforces it; nothing here is sent to the server.
class BlockerScreen extends ConsumerStatefulWidget {
  const BlockerScreen({super.key});

  @override
  ConsumerState<BlockerScreen> createState() => _BlockerScreenState();
}

class _BlockerScreenState extends ConsumerState<BlockerScreen>
    with WidgetsBindingObserver {
  StreamSubscription<SyncResult>? _syncs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The blocker decides from the numbers the last sync brought, so say what it decides again when a sync lands.
    _syncs = ref.read(bridgeProvider).syncFinished.listen((_) {
      if (mounted) ref.invalidate(blockerStatusProvider);
    });
  }

  @override
  void dispose() {
    _syncs?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's Accessibility settings: has the service been switched on?
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(blockerStatusProvider);
    }
  }

  BlockerController get _controller => ref.read(blockerConfigProvider.notifier);

  Future<void> _toggle(BlockerConfig c, bool on) async {
    await _controller.save(c.copyWith(enabled: on));
    if (!on || !mounted) return;
    final status = await ref.read(blockerStatusProvider.future);
    if (!status.serviceEnabled && mounted) await _turnOnService();
  }

  /// Explains what the accessibility service does and asks first, then opens Android's settings.
  Future<void> _turnOnService() async {
    final agreed = await showBlockerDisclosure(context);
    if (agreed == true) {
      await ref.read(bridgeProvider).openAccessibilitySettings();
    }
  }

  Future<void> _addWindow(BlockerConfig c, {UseWindow? preset}) async {
    final w = await showUseWindowSheet(
      context,
      initial: preset,
      existing: c.windows,
    );
    if (w == null || !mounted) return;
    await _controller.save(c.copyWith(windows: [...c.windows, w]));
  }

  Future<void> _editWindow(BlockerConfig c, UseWindow old) async {
    final others = c.windows.where((w) => w != old).toList();
    final w = await showUseWindowSheet(context, initial: old, existing: others);
    if (w == null || !mounted) return;
    await _controller.save(
      c.copyWith(windows: [for (final x in c.windows) x == old ? w : x]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(blockerConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Block distracting apps')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(blockerConfigProvider);
          ref.invalidate(blockerStatusProvider);
          ref.invalidate(installedAppsProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            AsyncBody<BlockerConfig>(
              value: config,
              rows: 3,
              onRetry: () => ref.invalidate(blockerConfigProvider),
              data: (c) => Column(
                children: [
                  _StatusCard(
                    config: c,
                    onToggle: (on) => _toggle(c, on),
                    onTurnOnService: _turnOnService,
                  ),
                  _AppsCard(config: c),
                  _ModeCard(config: c, onChange: _controller.save),
                  if (c.mode == BlockMode.setTimes)
                    _UseTimesCard(
                      config: c,
                      onAdd: (preset) => _addWindow(c, preset: preset),
                      onEdit: (w) => _editWindow(c, w),
                      onRemove: (w) => _controller.save(
                        c.copyWith(
                          windows: c.windows.where((x) => x != w).toList(),
                        ),
                      ),
                    ),
                  const _HowItWorks(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The disclosure Google Play requires before sending someone to the Accessibility settings: what it is used for, what it is not.
Future<bool?> showBlockerDisclosure(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Allow TaskRelay to block apps'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To block the apps you choose, TaskRelay uses Android’s Accessibility Service.',
            ),
            SizedBox(height: 12),
            Text(
              '• It is used only to notice which app you open, so a block screen can appear for the apps you picked.',
            ),
            SizedBox(height: 6),
            Text(
              '• It does not read what is on your screen, what you type, your passwords or your messages.',
            ),
            SizedBox(height: 6),
            Text(
              '• Your list of apps and your rules stay on this phone. Nothing about them is sent to TaskRelay or anyone else.',
            ),
            SizedBox(height: 6),
            Text(
              '• You can turn it off at any time in Android Settings, Accessibility.',
            ),
            SizedBox(height: 12),
            Text(
              'Android will then show its standard warning about “full control”. That warning is the same for every accessibility service: TaskRelay uses only what is described above.',
            ),
            SizedBox(height: 12),
            Text(
              'On the next screen, find TaskRelay and switch it on.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Agree and open settings'),
        ),
      ],
    ),
  );
}

String _clock(BuildContext context, int minute) =>
    fmtClock(context, minutesToHhmm(minute));

class _StatusCard extends ConsumerWidget {
  const _StatusCard({
    required this.config,
    required this.onToggle,
    required this.onTurnOnService,
  });
  final BlockerConfig config;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTurnOnService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tr;
    final status = ref.watch(blockerStatusProvider).valueOrNull;
    final needsService =
        config.enabled && status != null && !status.serviceEnabled;
    return SurfaceCard(
      semanticLabel: 'Blocker status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Block distracting apps',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              config.enabled
                  ? 'On'
                  : 'Keep them closed until your tasks are done, or open them only at times you choose.',
              style: TextStyle(color: t.muted),
            ),
            value: config.enabled,
            onChanged: onToggle,
          ),
          if (needsService) ...[
            const SizedBox(height: 8),
            _NeedsAccess(onTurnOn: onTurnOnService),
          ] else if (config.enabled && status != null) ...[
            const SizedBox(height: 4),
            if (config.packages.isEmpty)
              const IconText(
                Icons.info_outline,
                'Choose the apps to block below.',
                style: TextStyle(fontWeight: FontWeight.w700),
              )
            else
              IconText(
                status.decision.blocked
                    ? Icons.lock_outline
                    : Icons.lock_open_outlined,
                blockerStatusText(
                  status.decision,
                  clock: (m) => _clock(context, m),
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
        ],
      ),
    );
  }
}

/// Nothing is blocked until TaskRelay is switched on in Android's Accessibility settings.
class _NeedsAccess extends StatelessWidget {
  const _NeedsAccess({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.onSurface,
            width: 6,
          ),
          top: BorderSide(color: t.fieldBorder),
          right: BorderSide(color: t.fieldBorder),
          bottom: BorderSide(color: t.fieldBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconText(
            Icons.warning_amber_outlined,
            'One more step: nothing is blocked yet',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Switch TaskRelay on in Android’s Accessibility settings so it can notice when you open a blocked app.',
          ),
          const SizedBox(height: 8),
          Text(
            'If the switch is greyed out, open TaskRelay’s app info, use the three-dot menu and choose “Allow restricted settings”, then try again.',
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onTurnOn,
            child: const Text('Turn on in Settings'),
          ),
        ],
      ),
    );
  }
}

class _AppsCard extends ConsumerWidget {
  const _AppsCard({required this.config});
  final BlockerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tr;
    final labels = {
      for (final a
          in ref.watch(installedAppsProvider).valueOrNull ??
              const <InstalledApp>[])
        a.package: a.label,
    };
    return SurfaceCard(
      semanticLabel: 'Apps to block',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Apps to block'),
          if (config.packages.isEmpty)
            Text('None chosen yet.', style: TextStyle(color: t.muted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in config.packages)
                  Chip(
                    label: Text(
                      labels[p] ?? p,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppPickerScreen()),
            ),
            icon: const Icon(Icons.apps_outlined, size: 18),
            label: Text(
              config.packages.isEmpty ? 'Choose apps' : 'Change apps',
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.config, required this.onChange});
  final BlockerConfig config;
  final Future<void> Function(BlockerConfig) onChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    Widget option(BlockMode mode, String title, String detail) =>
        RadioListTile<BlockMode>(
          value: mode,
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(detail, style: TextStyle(color: t.muted)),
        );
    return SurfaceCard(
      semanticLabel: 'When to block',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('When to block'),
          RadioGroup<BlockMode>(
            groupValue: config.mode,
            onChanged: (m) {
              if (m != null) onChange(config.copyWith(mode: m));
            },
            child: Column(
              children: [
                option(
                  BlockMode.untilDone,
                  'Until my tasks are done',
                  'Blocked while any task is left today. When the last one is done, everything unlocks.',
                ),
                option(
                  BlockMode.freeTime,
                  'While a task is running',
                  'Blocked while a task with a start time is on. Free the rest of the time.',
                ),
                option(
                  BlockMode.setTimes,
                  'Only at times I choose',
                  'Blocked except at the use times you set below. A running task always blocks.',
                ),
              ],
            ),
          ),
          if (config.mode == BlockMode.untilDone)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Count overdue tasks too'),
              subtitle: Text(
                'Overdue tasks keep the apps blocked until you finish or move them.',
                style: TextStyle(color: t.muted),
              ),
              value: config.countOverdue,
              onChanged: (v) => onChange(config.copyWith(countOverdue: v)),
            ),
          if (config.mode == BlockMode.setTimes)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unlock everything when all tasks are done'),
              subtitle: Text(
                'Once nothing is left for today, the apps open even outside the use times.',
                style: TextStyle(color: t.muted),
              ),
              value: config.unlockWhenDone,
              onChanged: (v) => onChange(config.copyWith(unlockWhenDone: v)),
            ),
        ],
      ),
    );
  }
}

class _UseTimesCard extends ConsumerWidget {
  const _UseTimesCard({
    required this.config,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });
  final BlockerConfig config;
  final ValueChanged<UseWindow?> onAdd;
  final ValueChanged<UseWindow> onEdit;
  final ValueChanged<UseWindow> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tr;
    // The gaps between today's timed tasks: where a use time costs no work. Only from now on, nobody plans the past.
    final now = ref.watch(clockProvider)();
    final tasks =
        ref.watch(dayViewProvider(todayYmd(now))).valueOrNull?.tasks ??
        const <Task>[];
    final from = (now.hour * 60 + now.minute).clamp(360, 1380);
    final free = freeSlots(
      tasks.map((x) => x.block).whereType<TimeBlock>(),
      from: from,
    );
    return SurfaceCard(
      semanticLabel: 'Use times',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Use times'),
          if (config.windows.isEmpty)
            const IconText(
              Icons.info_outline,
              'No use times yet: these apps stay blocked all day.',
              style: TextStyle(fontWeight: FontWeight.w700),
            )
          else
            for (final w in config.windows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  useWindowLabel(w, clock: (m) => _clock(context, m)),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => onEdit(w),
                trailing: IconButton(
                  tooltip:
                      'Remove the use time ${useWindowLabel(w, clock: (m) => _clock(context, m))}',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(w),
                ),
              ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: config.windows.length >= maxUseWindows
                ? null
                : () => onAdd(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a use time'),
          ),
          if (free.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Free for the rest of today (no task scheduled)',
              style: TextStyle(
                color: t.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final g in free.take(4))
                  ActionChip(
                    label: Text(
                      '${_clock(context, g.start)} – ${_clock(context, g.end)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () => onAdd(
                      UseWindow(
                        start: minutesToHhmm(g.start),
                        end: minutesToHhmm(g.end),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      'TaskRelay only notices which app you open, never what is on your screen. Your choices stay on this phone. Settings and Phone can never be blocked, so you can always change this or call for help.',
      style: TextStyle(color: context.tr.muted, fontSize: 12),
    ),
  );
}

/// Add or edit one use time: when it starts and ends, and on which days. Resolves with the window, or null.
Future<UseWindow?> showUseWindowSheet(
  BuildContext context, {
  UseWindow? initial,
  required List<UseWindow> existing,
}) {
  return showModalBottomSheet<UseWindow>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _UseWindowSheet(initial: initial, existing: existing),
  );
}

class _UseWindowSheet extends StatefulWidget {
  const _UseWindowSheet({this.initial, required this.existing});
  final UseWindow? initial;
  final List<UseWindow> existing;

  @override
  State<_UseWindowSheet> createState() => _UseWindowSheetState();
}

class _UseWindowSheetState extends State<_UseWindowSheet> {
  late TimeOfDay? _start;
  late TimeOfDay? _end;
  late final Set<int> _days;

  @override
  void initState() {
    super.initState();
    final w = widget.initial;
    _start = w == null
        ? const TimeOfDay(hour: 18, minute: 0)
        : fromHhmm(w.start);
    _end = w == null ? const TimeOfDay(hour: 19, minute: 0) : fromHhmm(w.end);
    _days = {
      ...(w?.days ?? const [1, 2, 3, 4, 5, 6, 7]),
    };
  }

  static int _minute(TimeOfDay t) => t.hour * 60 + t.minute;

  bool get _orderOk => _minute(_end!) > _minute(_start!);
  UseWindow get _window => UseWindow(
    start: toHhmm(_start!),
    end: toHhmm(_end!),
    days: (_days.toList()..sort()),
  );
  bool get _clash => widget.existing.any((w) => windowsOverlap(w, _window));
  bool get _valid => _orderOk && _days.isNotEmpty && !_clash;

  Future<void> _pick({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end)!,
      helpText: start ? 'Use time starts' : 'Use time ends',
    );
    if (picked != null) {
      setState(() => start ? _start = picked : _end = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = shortWeekdays();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Add a use time' : 'Edit use time',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'The blocked apps may be used between these times. A task that is running still blocks them.',
              style: TextStyle(color: context.tr.muted),
            ),
            const SizedBox(height: 12),
            ClockRow(
              icon: Icons.play_arrow_outlined,
              label: 'From',
              value: _start,
              onPick: () => _pick(start: true),
            ),
            const SizedBox(height: 6),
            ClockRow(
              icon: Icons.stop_outlined,
              label: 'Until',
              value: _end,
              onPick: () => _pick(start: false),
            ),
            if (!_orderOk) const _Problem('The end must be after the start.'),
            const SizedBox(height: 12),
            Text(
              'Days',
              style: TextStyle(
                color: context.tr.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(names[i]),
                    labelStyle: chipLabel(
                      context,
                      selected: _days.contains(i + 1),
                    ),
                    selected: _days.contains(i + 1),
                    onSelected: (on) => setState(
                      () => on ? _days.add(i + 1) : _days.remove(i + 1),
                    ),
                  ),
              ],
            ),
            // a Wrap, not a Row: three buttons do not fit side by side on a 360dp phone, let alone at big text sizes
            Wrap(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => _days
                      ..clear()
                      ..addAll([1, 2, 3, 4, 5, 6, 7]),
                  ),
                  child: const Text('Every day'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _days
                      ..clear()
                      ..addAll([1, 2, 3, 4, 5]),
                  ),
                  child: const Text('Weekdays'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _days
                      ..clear()
                      ..addAll([6, 7]),
                  ),
                  child: const Text('Weekends'),
                ),
              ],
            ),
            if (_days.isEmpty) const _Problem('Pick at least one day.'),
            if (_orderOk && _days.isNotEmpty && _clash)
              const _Problem('This overlaps another use time.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _valid
                        ? () => Navigator.of(context).pop(_window)
                        : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: IconText(
      Icons.warning_amber_outlined,
      text,
      iconSize: 14,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
}
