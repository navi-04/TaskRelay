import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme/app_theme.dart';
import '../data/api_exception.dart';
import '../data/models.dart';
import '../state/providers.dart';

/// A bordered surface (the app's card).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = const EdgeInsets.only(bottom: 16), this.semanticLabel});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: context.tr.border),
      ),
      child: child,
    );
    return semanticLabel == null ? card : Semantics(container: true, label: semanticLabel, child: card);
  }
}

/// Label style for a chip. The colour is chosen HERE from `selected`, as a plain Color. Relying on the theme to resolve a
/// state-dependent label colour left the unselected labels blank on a real phone (white on white in the White theme), while the same
/// chips looked fine in widget tests. A plain colour has nothing to resolve.
TextStyle chipLabel(BuildContext context, {required bool selected}) => TextStyle(
      color: selected ? context.tr.accentInk : Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );

/// A clock time: one button that opens the time picker. With [onClear] the time is optional and gets a way to remove it.
class ClockRow extends StatelessWidget {
  const ClockRow({super.key, required this.icon, required this.label, required this.value, required this.onPick, this.onClear});
  final IconData icon;
  final String label;
  final TimeOfDay? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: onPick, icon: Icon(icon), label: Text(value == null ? 'Add ${label.toLowerCase()}' : '$label: ${value!.format(context)}'))),
        if (value != null && onClear != null) IconButton(tooltip: 'Remove ${label.toLowerCase()}', icon: const Icon(Icons.close), onPressed: onClear),
      ]);
}

/// Text with a leading Material icon. Use this instead of an emoji: Android draws emoji in full colour,
/// and this app is strictly black and white (test/monochrome_test.dart fails the build if one slips in).
class IconText extends StatelessWidget {
  const IconText(this.icon, this.text, {super.key, this.style, this.iconSize = 16});
  final IconData icon;
  final String text;
  final TextStyle? style;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.merge(style).color;
    return Text.rich(
      TextSpan(children: [
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(icon, size: MediaQuery.textScalerOf(context).scale(iconSize), color: color)),
        TextSpan(text: ' $text'),
      ]),
      style: style,
    );
  }
}

/// Asks for some text in a dialog; returns it trimmed, or null when cancelled.
/// The dialog OWNS its controller. Disposing a controller right after `await showDialog` breaks the dialog's closing animation
/// ("TextEditingController used after being disposed": the red error screen), so it is disposed with the dialog's State instead.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int maxLength = 40,
  int maxLines = 1,
  String confirm = 'Save',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, hint: hint, maxLength: maxLength, maxLines: maxLines, confirm: confirm),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.hint, required this.maxLength, required this.maxLines, required this.confirm});
  final String title;
  final String initial;
  final String? hint;
  final int maxLength;
  final int maxLines;
  final String confirm;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(controller: _ctl, autofocus: true, maxLength: widget.maxLength, maxLines: widget.maxLines, decoration: InputDecoration(hintText: widget.hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _ctl.text.trim()), child: Text(widget.confirm)),
        ],
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// An error that stays readable without colour: heavy left rule, a mark, bold text.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        // No borderRadius: Flutter refuses to paint a radius on a border whose sides differ (it throws while painting, and the whole
        // banner came out blank on the phone).
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: text, width: 6), top: BorderSide(color: context.tr.fieldBorder), right: BorderSide(color: context.tr.fieldBorder), bottom: BorderSide(color: context.tr.fieldBorder)),
        ),
        child: Row(children: [
          Expanded(child: IconText(Icons.warning_amber_outlined, message, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.check_circle_outline});
  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
        child: Column(children: [
          Icon(icon, size: 40, color: context.tr.muted),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (message != null) ...[const SizedBox(height: 4), Text(message!, textAlign: TextAlign.center, style: TextStyle(color: context.tr.muted))],
        ]),
      );
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: context.tr.input, borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
            ),
        ]),
      );
}

/// Loading / error-with-retry / data, in one place. If a refresh fails but there is data, the data stays and a banner
/// says so, so a flaky connection never blanks the screen. Place inside a scrollable.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, required this.onRetry, this.rows = 4});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final int rows;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final child = data(value.requireValue);
      if (value.hasError && !value.isLoading) {
        return Column(children: [ErrorBanner(message: 'Couldn’t refresh. ${friendlyError(value.error!)}', onRetry: onRetry), child]);
      }
      return child;
    }
    if (value.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 8),
          Text(friendlyError(value.error!), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
    }
    return SkeletonRows(rows: rows);
  }
}

/// A circular progress ring with a centre label.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.percent, required this.label, this.size = 72});
  final double percent;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0, 100).toDouble();
    return Semantics(
      label: '${p.round()} percent complete',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(p / 100, context.tr.accent, context.tr.track),
          child: Center(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.fill, this.track);
  final double fraction;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arc, 0, math.pi * 2, false, base);
    if (fraction > 0) {
      canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * fraction, false, base..color = fill..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.fill != fill || old.track != track;
}

/// The last 7 days of a repeating task. filled = done, crossed = missed, dashed = skipped, ring = to do, tiny = not scheduled.
class HabitDots extends StatelessWidget {
  const HabitDots({super.key, required this.habit});
  final Habit habit;

  static const _words = {'done': 'done', 'missed': 'missed', 'skipped': 'skipped', 'pending': 'to do today', 'none': 'not scheduled'};

  @override
  Widget build(BuildContext context) {
    final summary = habit.last7.map((d) => '${fmtDay(d.date)} ${_words[d.state] ?? d.state}').join(', ');
    return Semantics(
      label: 'Last 7 days: $summary',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final d in habit.last7)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: CustomPaint(size: const Size(11, 11), painter: _DotPainter(d.state, Theme.of(context).colorScheme.onSurface, context.tr.muted, context.tr.track)),
          ),
      ]),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.state, this.ink, this.muted, this.track);
  final String state;
  final Color ink;
  final Color muted;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ink;
    switch (state) {
      case 'done':
        canvas.drawCircle(c, r, Paint()..color = ink);
      case 'missed':
        canvas.drawCircle(c, r, ring);
        canvas.drawLine(Offset(c.dx - r * .6, c.dy - r * .6), Offset(c.dx + r * .6, c.dy + r * .6), ring);
        canvas.drawLine(Offset(c.dx - r * .6, c.dy + r * .6), Offset(c.dx + r * .6, c.dy - r * .6), ring);
      case 'skipped':
        final dash = ring..color = muted;
        for (var a = 0.0; a < math.pi * 2; a += math.pi / 3) {
          canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi / 6, false, dash);
        }
      case 'pending':
        canvas.drawCircle(c, r, ring..color = muted);
      default:
        canvas.drawCircle(c, 2, Paint()..color = track);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.state != state || old.ink != ink;
}

// ── snackbars ────────────────────────────────────────────────────────────────────────────────────

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// "Deleted X · Undo": the undo is a real call, so a failure is reported, never swallowed.
void showUndo(BuildContext context, UndoAction action) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(action.message),
      duration: const Duration(seconds: 7),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await action.undo();
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
          }
        },
      ),
    ));
}

/// A confirm/choice sheet: returns the chosen id or null if dismissed.
Future<String?> askChoice(BuildContext context, {required String title, String? message, required List<({String id, String label, bool destructive})> choices}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message, style: TextStyle(color: ctx.tr.muted))),
        const SizedBox(height: 16),
        for (final c in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: c.destructive
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(side: BorderSide(color: Theme.of(ctx).colorScheme.onSurface, width: 2)),
                    onPressed: () => Navigator.pop(ctx, c.id),
                    child: Text(c.label),
                  )
                : FilledButton(onPressed: () => Navigator.pop(ctx, c.id), child: Text(c.label)),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ]),
    ),
  );
}
