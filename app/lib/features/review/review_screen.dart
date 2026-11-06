import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';
import '../../state/providers.dart';

/// A week in review, with a ready-made "plan next week" request for Claude.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  String? _weekStart; // null = the last 7 days

  Future<void> _copyPrompt(Review r) async {
    final me = ref.read(meProvider).valueOrNull;
    final link = me != null && me.aiAccessEnabled ? '\n\nMy TaskRelay manual (treat the link like a password): ${Config.apiBase}/api/ai?uid=${me.aiAccessId}' : '';
    await Clipboard.setData(ClipboardData(text: r.planPrompt + link));
    if (!mounted) return;
    showMessage(context, me != null && me.aiAccessEnabled ? 'Prompt copied. Paste it into Claude.' : 'Prompt copied. Turn on Claude access in Profile so it can use your tasks.');
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(reviewProvider(_weekStart));
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly review')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reviewProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            AsyncBody<Review>(
              value: review,
              onRetry: () => ref.invalidate(reviewProvider),
              data: (r) {
                final canNext = shiftYmd(r.from, 7).compareTo(todayYmd()) <= 0;
                final maxPri = r.byPriority.fold<int>(1, (m, p) => p.planned > m ? p.planned : m);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconButton(tooltip: 'Previous week', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _weekStart = shiftYmd(r.from, -7))),
                    Expanded(child: Text('${fmtDay(r.from)} – ${fmtDay(r.to)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                    IconButton(tooltip: 'Next week', icon: const Icon(Icons.chevron_right), onPressed: canNext ? () => setState(() => _weekStart = shiftYmd(r.from, 7)) : null),
                  ]),
                  if (r.totals.planned == 0)
                    const SurfaceCard(child: EmptyState(title: 'Nothing was planned this week', message: 'Plan some tasks and come back for your review.', icon: Icons.insights_outlined))
                  else ...[
                    SurfaceCard(
                      semanticLabel: 'Summary',
                      child: Row(children: [
                        ProgressRing(percent: r.totals.completionPct.toDouble(), label: '${r.totals.completionPct}%'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r.totals.done} of ${r.totals.planned} tasks done', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('${r.totals.onTimePct}% on the day · ${fmtMinutes(r.totals.doneMin)} of ${fmtMinutes(r.totals.plannedMin)}', style: TextStyle(color: t.muted)),
                            Text('${r.streak > 0 ? '${plural(r.streak, 'day')} streak' : 'No streak right now'}${r.overdueCount > 0 ? ' · ${r.overdueCount} overdue' : ''}', style: TextStyle(color: t.muted)),
                          ]),
                        ),
                      ]),
                    ),
                    SurfaceCard(
                      semanticLabel: 'Day by day',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionTitle('Day by day'),
                        for (final d in r.days) _DayRow(day: d),
                      ]),
                    ),
                    SurfaceCard(
                      semanticLabel: 'Insights',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionTitle('Insights'),
                        if (r.bestHours.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('You finish most tasks around ${r.bestHours.map((h) => fmtClock(context, '${h.hour.toString().padLeft(2, '0')}:00')).join(', ')}.')),
                        if (r.top3Total > 0) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Top 3: ${r.top3Done} of ${r.top3Total} done across ${plural(r.top3Days, 'day')}.')),
                        if (r.byPriority.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('By priority', style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                          for (final p in r.byPriority)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [Expanded(child: Text(p.priority)), Text('${p.done}/${p.planned}', style: TextStyle(color: t.muted))]),
                                const SizedBox(height: 4),
                                Semantics(
                                  label: '${p.priority}: ${p.done} of ${p.planned} done',
                                  excludeSemantics: true,
                                  child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 8, value: p.planned == 0 ? 0 : (p.planned / maxPri) * (p.done / p.planned))),
                                ),
                              ]),
                            ),
                        ],
                        if (r.mostMissed.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Repeating tasks you missed most', style: TextStyle(color: t.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                          for (final m in r.mostMissed) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${m.title} · ${m.missed} of ${m.planned}')),
                        ],
                      ]),
                    ),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _Bullets(title: 'Wins', items: r.wins, empty: 'Nothing yet.')),
                      const SizedBox(width: 12),
                      Expanded(child: _Bullets(title: 'To improve', items: r.misses, empty: 'Nothing missed. Nice.')),
                    ]),
                  ],
                  SurfaceCard(
                    semanticLabel: 'Plan next week',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionTitle('Plan next week with Claude'),
                      Text('Copies a summary of this week plus your Claude link. Paste it into Claude to plan a realistic Top 3 for each day.', style: TextStyle(color: t.muted)),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: () => _copyPrompt(r), icon: const Icon(Icons.copy), label: const Text('Copy prompt for Claude')),
                    ]),
                  ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});
  final DayStat day;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 92, child: Text(fmtDay(day.date), style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Semantics(
            label: '${fmtDay(day.date)}: ${day.done} of ${day.planned} done',
            excludeSemantics: true,
            child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 8, value: day.planned == 0 ? 0 : day.done / day.planned)),
          ),
        ),
        SizedBox(width: 56, child: Text(day.planned == 0 ? '–' : '${day.done}/${day.planned}', textAlign: TextAlign.right, style: TextStyle(color: t.muted, fontSize: 13))),
      ]),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.title, required this.items, required this.empty});
  final String title;
  final List<String> items;
  final String empty;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        semanticLabel: title,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(title),
          if (items.isEmpty) Text(empty, style: TextStyle(color: context.tr.muted)) else for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $i')),
        ]),
      );
}
