'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useState } from 'react';
import { BarChart } from '@/components/Charts';
import { useToast } from '@/components/Feedback';
import Shell, { useMe } from '@/components/Shell';
import { EmptyState, ErrorBanner, ProgressRing, Skeleton } from '@/components/ui';
import { fmtClock, fmtDay, fmtMin, pad2, plural, shiftDate } from '@/lib/web/format';
import { useApi } from '@/lib/web/hooks';
import type { WeeklyReview } from '@/lib/services/review';

export default function ReviewPage() {
  return (
    <Shell>
      <h1>Weekly review</h1>
      <Suspense fallback={<Skeleton rows={4} />}>
        <Review />
      </Suspense>
    </Shell>
  );
}

const localToday = () => {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
};

function Review() {
  const router = useRouter();
  const params = useSearchParams();
  const toast = useToast();
  const { me } = useMe();
  const [copied, setCopied] = useState(false);

  const requested = params.get('week_start');
  const weekStart = requested && /^\d{4}-\d{2}-\d{2}$/.test(requested) ? requested : null;
  const { data: r, error, loading, reload } = useApi<WeeklyReview>(`/review${weekStart ? `?week_start=${weekStart}` : ''}`);

  if (!r) return error ? <ErrorBanner message={error} onRetry={() => void reload()} /> : <Skeleton rows={4} />;

  const go = (from: string) => router.push(`/review?week_start=${from}`);
  const canNext = shiftDate(r.from, 7) <= localToday();
  const maxPri = Math.max(1, ...r.by_priority.map((p) => p.planned));

  async function copyPrompt() {
    const link = me.ai_access_enabled ? `\n\nMy TaskRelay manual (treat the link like a password): ${location.origin}/api/ai?uid=${me.ai_access_id}` : '';
    try {
      await navigator.clipboard.writeText(r!.plan_prompt + link);
      setCopied(true);
      toast(me.ai_access_enabled ? 'Prompt copied. Paste it into Claude.' : 'Prompt copied. Turn on Claude access in Profile so it can use your tasks.');
    } catch {
      toast('Could not copy. Select the text and copy it manually.');
    }
  }

  return (
    <div style={{ opacity: loading ? 0.6 : 1 }} aria-busy={loading}>
      <div className="spread" style={{ marginBottom: 12 }}>
        <button className="icon" aria-label="Previous week" onClick={() => go(shiftDate(r.from, -7))}>‹</button>
        <strong aria-live="polite">{fmtDay(r.from)} – {fmtDay(r.to)}</strong>
        <button className="icon" aria-label="Next week" disabled={!canNext} onClick={() => go(shiftDate(r.from, 7))}>›</button>
      </div>
      {error && <ErrorBanner message={`Couldn’t refresh: ${error}`} onRetry={() => void reload()} />}

      {r.totals.planned === 0 ? (
        <section className="card"><EmptyState title="Nothing was planned this week">Plan some tasks and come back for your review.</EmptyState></section>
      ) : (
        <>
          <section className="card" aria-label="Summary">
            <div className="row">
              <ProgressRing percent={r.totals.completion_pct} label={`${r.totals.completion_pct}%`} />
              <div className="grow">
                <strong>{r.totals.done} of {r.totals.planned} tasks done</strong>
                <div className="muted">{r.totals.on_time_pct}% on the day · {fmtMin(r.totals.done_min)} of {fmtMin(r.totals.planned_min)}</div>
                <div className="muted">{r.streak > 0 ? `${plural(r.streak, 'day')} streak` : 'No streak right now'}{r.overdue_count > 0 && ` · ${r.overdue_count} overdue`}</div>
              </div>
            </div>
          </section>

          <section className="card" aria-label="Day by day">
            <h2>Day by day</h2>
            <BarChart days={r.days} />
          </section>

          <section className="card" aria-label="Insights">
            <h2>Insights</h2>
            {r.best_hours.length > 0 && (
              <p>You finish most tasks around <strong>{r.best_hours.map((h) => fmtClock(`${pad2(h.hour)}:00`)).join(', ')}</strong>.</p>
            )}
            {r.top3.total > 0 && <p>Top 3: <strong>{r.top3.done} of {r.top3.total}</strong> done across {plural(r.top3.days_set, 'day')}.</p>}
            {r.by_priority.length > 0 && (
              <>
                <h3>By priority</h3>
                {r.by_priority.map((p) => (
                  <div key={p.priority} style={{ marginBottom: 8 }}>
                    <div className="spread small"><span>{p.priority}</span><span className="muted">{p.done}/{p.planned}</span></div>
                    <div className="bar-track" role="img" aria-label={`${p.priority}: ${p.done} of ${p.planned} done`}>
                      <div className="bar-fill" style={{ width: `${(p.planned / maxPri) * (p.planned === 0 ? 0 : (p.done / p.planned) * 100)}%` }} />
                    </div>
                  </div>
                ))}
              </>
            )}
            {r.most_missed.length > 0 && (
              <>
                <h3>Repeating tasks you missed most</h3>
                <ul style={{ margin: 0, paddingLeft: 20 }}>
                  {r.most_missed.map((m) => <li key={m.task_id}>{m.title} <span className="muted">· {m.missed} of {m.planned}</span></li>)}
                </ul>
              </>
            )}
          </section>

          <div className="row" style={{ alignItems: 'flex-start' }}>
            <section className="card grow" aria-label="Wins">
              <h2>Wins</h2>
              {r.wins.length ? <ul style={{ margin: 0, paddingLeft: 20 }}>{r.wins.map((w) => <li key={w}>{w}</li>)}</ul> : <p className="muted">Nothing yet.</p>}
            </section>
            <section className="card grow" aria-label="Misses">
              <h2>To improve</h2>
              {r.misses.length ? <ul style={{ margin: 0, paddingLeft: 20 }}>{r.misses.map((w) => <li key={w}>{w}</li>)}</ul> : <p className="muted">Nothing missed. Nice.</p>}
            </section>
          </div>
        </>
      )}

      <section className="card" aria-label="Plan next week">
        <h2>Plan next week with Claude</h2>
        <p className="muted">Copies a summary of this week plus your Claude link. Paste it into Claude to plan a realistic Top 3 for each day.</p>
        <button className="primary" onClick={copyPrompt}>{copied ? 'Copied ✓' : 'Copy prompt for Claude'}</button>
      </section>
    </div>
  );
}
