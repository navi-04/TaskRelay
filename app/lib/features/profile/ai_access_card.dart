import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_exception.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

const _prompts = [
  ('Plan my day', 'Look at my TaskRelay overview and help me plan today. Suggest a realistic Top 3, point out anything over my daily limit, and ask me before changing anything.'),
  ('Pick my Top 3', "Read today's tasks and propose my Top 3: the most important ones I can realistically finish. If I agree, set them as my Top 3."),
  ('Sort out overdue', 'List my overdue tasks and, for each, suggest whether to do it today, move it to another day, or delete it. Ask me before moving or deleting anything.'),
  ('Weekly review', 'Read my weekly review and my habits. Tell me what went well and what to improve, then help me plan next week.'),
  ('Set up a routine', 'Help me set up a weekly routine as repeating tasks on specific weekdays. Ask me what and when, then create them and tell me exactly what you added.'),
];

const _kindWord = {'created': 'added', 'updated': 'changed', 'deleted': 'deleted', 'completed': 'completed', 'rescheduled': 'moved', 'restored': 'restored'};

/// Claude access: switch it on/off, copy the ID or a ready-made prompt, regenerate it, see what Claude changed.
class AiAccessCard extends ConsumerStatefulWidget {
  const AiAccessCard({super.key});

  @override
  ConsumerState<AiAccessCard> createState() => _AiAccessCardState();
}

class _AiAccessCardState extends ConsumerState<AiAccessCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn, {String? done}) async {
    setState(() => _busy = true);
    try {
      await fn();
      ref.invalidate(meProvider);
      if (done != null && mounted) showMessage(context, done);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, '$what copied');
  }

  Future<void> _regenerate() async {
    final choice = await askChoice(context, title: 'Create a new ID?', message: 'The current one stops working immediately. Anything using it (for example a Claude chat) will need the new one.', choices: [(id: 'yes', label: 'Create new ID', destructive: true)]);
    if (choice == null) return;
    await _run(() => ref.read(apiProvider).regenerateAiAccess().then((_) {}), done: 'New ID created. The old one no longer works.');
  }

  Future<void> _restore(ActivityItem i) async {
    try {
      await ref.read(taskActionsProvider).restore(i.taskId);
      ref.invalidate(activityProvider);
      if (mounted) showMessage(context, 'Restored “${i.title}”');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final me = ref.watch(meProvider);
    final activity = ref.watch(activityProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SurfaceCard(
        semanticLabel: 'Claude access',
        child: AsyncBody<Me>(
          value: me,
          rows: 2,
          onRetry: () => ref.invalidate(meProvider),
          data: (m) {
            final link = '${Config.apiBase}/api/ai?uid=${m.aiAccessId}';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Claude access', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Switch(value: m.aiAccessEnabled, onChanged: _busy ? null : (v) => _run(() => ref.read(apiProvider).setAiEnabled(v).then((_) {}))),
              ]),
              Text('Give this to Claude (or any assistant that can open links). It can read and change your tasks, nothing else. Treat it like a password: anyone who has it can read, add, change and delete your tasks.', style: TextStyle(color: t.muted)),
              const SizedBox(height: 12),
              Text('Your AI access ID', style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SelectableText(m.aiAccessId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: _busy ? null : () => _copy(m.aiAccessId, 'ID'), icon: const Icon(Icons.copy, size: 18), label: const Text('Copy ID')),
                FilledButton.icon(
                  onPressed: _busy || !m.aiAccessEnabled ? null : () => _copy('Use my TaskRelay API to manage my tasks.\nRead the manual first: $link\nFollow its rules. Ask me before deleting anything or changing many tasks at once.', 'Prompt'),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Copy prompt for Claude'),
                ),
                OutlinedButton(onPressed: _busy ? null : _regenerate, style: OutlinedButton.styleFrom(side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 2)), child: const Text('Regenerate')),
              ]),
              const SizedBox(height: 8),
              Text('${m.aiLastUsedAt == null ? 'Not used yet.' : 'Last used ${ago(m.aiLastUsedAt!)}.'} If you didn’t expect that, regenerate the ID.', style: TextStyle(color: t.muted, fontSize: 12)),
              const SizedBox(height: 16),
              Text('Things to ask Claude', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Each button copies a ready-made request with your link attached.', style: TextStyle(color: t.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in _prompts) OutlinedButton(onPressed: m.aiAccessEnabled ? () => _copy('${p.$2}\n\nMy TaskRelay manual: $link', '“${p.$1}”') : null, child: Text(p.$1)),
              ]),
            ]);
          },
        ),
      ),
      SurfaceCard(
        semanticLabel: 'Recent changes by Claude',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Recent changes by Claude'),
          AsyncBody<List<ActivityItem>>(
            value: activity,
            rows: 2,
            onRetry: () => ref.invalidate(activityProvider),
            data: (items) => items.isEmpty
                ? Text('Nothing yet. When Claude changes your tasks, it shows up here.', style: TextStyle(color: t.muted))
                : Column(children: [
                    for (final i in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)), Text('${_kindWord[i.kind] ?? i.kind}${i.date == null ? '' : ' · ${i.date}'} · ${ago(i.at)}', style: TextStyle(color: t.muted, fontSize: 12))])),
                          if (i.kind == 'deleted') OutlinedButton(onPressed: () => _restore(i), child: const Text('Restore')),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}
