import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';

enum TaskMenu { edit, note, delete }

/// One task row. Pure: everything it needs arrives as arguments and everything it does leaves as a callback.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    this.priority,
    this.habit,
    this.busy = false,
    this.canStar = true,
    required this.onToggle,
    required this.onStar,
    required this.onMenu,
  });

  final Task task;
  final Label? priority;
  final Habit? habit;
  final bool busy;

  /// False when the Top 3 is full and this task is not in it.
  final bool canStar;
  final VoidCallback onToggle;
  final VoidCallback onStar;
  final ValueChanged<TaskMenu> onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final ink = Theme.of(context).colorScheme.onSurface;
    final starred = task.isTop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Check(done: task.isDone, busy: busy, label: '${task.isDone ? 'Mark not done' : 'Mark done'}: ${task.title}', onTap: busy ? null : onToggle),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                task.title,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: task.isDone ? t.muted : ink, decoration: task.isDone ? TextDecoration.lineThrough : null),
              ),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Chip(fmtMinutes(task.durationMin)),
                if (task.alarmTime != null) _Chip(fmtClock(context, task.alarmTime!), icon: task.reminderKind == 'alarm' ? Icons.alarm : Icons.notifications_none),
                if (task.isRepeating) _Chip('↻ ${repeatLabel(repeating: true, days: task.recurDays)}'),
                if (priority != null) _Chip(priority!.label),
                if (task.changedByClaude()) const _Chip('Claude', inverted: true),
              ]),
              // Not a chip: the dots have a fixed width and the text column can be as narrow as ~140dp on a small phone.
              if (habit != null && task.isRepeating)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                    if (habit!.currentStreak > 1)
                      IconText(Icons.local_fire_department_outlined, '${habit!.currentStreak}', iconSize: 14, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted))
                    else
                      Text('Last 7', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted)),
                    HabitDots(habit: habit!),
                  ]),
                ),
              if (task.dayNote != null && task.dayNote!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${task.dayNote}”', style: TextStyle(color: t.muted, fontSize: 13))),
            ]),
          ),
        ),
        IconButton(
          tooltip: starred ? 'Remove from Top 3' : (canStar ? 'Add to Top 3' : 'Your Top 3 is full'),
          isSelected: starred,
          icon: const Icon(Icons.star_border),
          selectedIcon: const Icon(Icons.star),
          onPressed: busy || (!starred && !canStar) ? null : onStar,
        ),
        PopupMenuButton<TaskMenu>(
          tooltip: 'More for ${task.title}',
          enabled: !busy,
          onSelected: onMenu,
          itemBuilder: (_) => [
            const PopupMenuItem(value: TaskMenu.edit, child: Text('Edit')),
            if (task.isDone) PopupMenuItem(value: TaskMenu.note, child: Text(task.dayNote == null ? 'Add a note' : 'Edit note')),
            const PopupMenuItem(value: TaskMenu.delete, child: Text('Delete')),
          ],
        ),
      ]),
    );
  }
}

/// A 48dp tap target around a round check mark.
class _Check extends StatelessWidget {
  const _Check({required this.done, required this.busy, required this.label, required this.onTap});
  final bool done;
  final bool busy;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Semantics(
      button: true,
      checked: done,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: done ? t.accent : Colors.transparent, border: Border.all(color: done ? t.accent : t.fieldBorder, width: 2)),
                    child: done ? Icon(Icons.check, size: 18, color: t.accentInk) : null,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.inverted = false, this.icon});
  final String text;
  final bool inverted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final ink = inverted ? t.accentInk : t.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: inverted ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: inverted ? t.accent : t.fieldBorder),
      ),
      // Labels are user-defined, so a long one must shorten instead of overflowing the row.
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: ink), const SizedBox(width: 4)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink))),
      ]),
    );
  }
}
