'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { BarChart } from '@/components/Charts';
import HabitDots from '@/components/HabitDots';
import Shell from '@/components/Shell';
import { EmptyState, ErrorBanner, Skeleton } from '@/components/ui';
import { addMonths, DAY_MARK, dayKind, monthGrid, monthStart, STREAK_BADGES } from '@/lib/web/calendar';
import { fmtDay, fmtMonth, plural, WEEKDAYS } from '@/lib/web/format';
import { useApi } from '@/lib/web/hooks';
import type { DayStat } from '@/lib/services/stats';
import type { HabitDto } from '@/lib/services/habits';

interface StatsView {
  today: string;
  from: string;
  to: string;
  days: DayStat[];
  streak: number;
  week: { planned: number; done: number; completion_pct: number; planned_min: number; done_min: number };
}

export default function CalendarPage() {
  return (
    <Shell>
      <h1>Calendar</h1>
      <Suspense fallback={<Skeleton rows={5} />}>
        <Calendar />
      </Suspense>
    </Shell>
  );
}

function Calendar() {
  const router = useRouter();
  const params = useSearchParams();
  const overview = useApi<StatsView>('/stats'); // gives "today" in the user's timezone, the streak and the last 7 days
  const today = overview.data?.today;

  const requested = params.get('month');
  const month = requested && /^\d{4}-\d{2}$/.test(requested) ? `${requested}-01` : today ? monthStart(today) : null;
  const grid = month ? monthGrid(month) : [];
  const range = grid.length ? `/stats?from=${grid[0].date}&to=${grid[grid.length - 1].date}` : null;
  const monthStats = useApi<StatsView>(today ? range : null);
  const habits = useApi<{ habits: HabitDto[] }>('/habits?days=90');

  if (!overview.data || !month || !today) {
    return overview.error ? <ErrorBanner message={overview.error} onRetry={() => void overview.reload()} /> : <Skeleton rows={5} />;
  }

  const byDate = new Map((monthStats.data?.days ?? []).map((d) => [d.date, d]));
  const go = (m: string) => router.push(`/calendar?month=${m.slice(0, 7)}`);

  // month summary: only days up to today can be "missed"
  const inMonth = grid.filter((g) => g.inMonth).map((g) => ({ date: g.date, stat: byDate.get(g.date) }));
  const kinds = inMonth.map(({ date, stat }) => (stat ? dayKind(stat, date, today) : 'none'));
  const count = (k: string) => kinds.filter((x) => x === k).length;
  const pastPlanned = inMonth.reduce((s, { date, stat }) => s + (stat && date <= today ? stat.planned : 0), 0);
  const pastDone = inMonth.reduce((s, { date, stat }) => s + (stat && date <= today ? stat.done : 0), 0);

  const { streak, days: week } = overview.data;

  return (
    <>
      <section className="card" aria-label="Month">
        <div className="spread" style={{ marginBottom: 8 }}>
          <button className="icon" aria-label="Previous month" onClick={() => go(addMonths(month, -1))}>‹</button>
          <h2 style={{ margin: 0 }} aria-live="polite">{fmtMonth(month)}</h2>
          <button className="icon" aria-label="Next month" onClick={() => go(addMonths(month, 1))}>›</button>
        </div>
        {monthStats.error && <ErrorBanner message={monthStats.error} onRetry={() => void monthStats.reload()} />}
        <div className="month" aria-busy={monthStats.loading}>
          {WEEKDAYS.map((d) => <div key={d} className="dow" aria-hidden="true">{d}</div>)}
          {grid.map(({ date, inMonth: inM }) => {
            const stat = byDate.get(date);
            const kind = stat ? dayKind(stat, date, today) : 'none';
            const { mark, label } = DAY_MARK[kind];
            const cls = ['day', inM ? '' : 'other', date === today ? 'today' : '', kind === 'full' ? 'full' : kind === 'partial' ? 'part' : kind === 'missed' ? 'missed' : ''].join(' ');
            return (
              <Link
                key={date}
                href={`/today?date=${date}`}
                className={cls}
                aria-label={`${fmtDay(date)}: ${stat && stat.planned > 0 ? `${label}, ${stat.done} of ${stat.planned} done` : 'no tasks'}${date === today ? ', today' : ''}`}
              >
                <span>{Number(date.slice(8))}</span>
                <span className="mark" aria-hidden="true">{mark || ' '}</span>
              </Link>
            );
          })}
        </div>
        <div className="row wrap muted small" style={{ marginTop: 12 }} aria-label="Legend">
          <span>✓ all done</span><span>◐ partly done</span><span>✕ missed</span><span>• planned</span>
        </div>
        <p className="muted" style={{ marginTop: 8, marginBottom: 0 }}>
          {plural(count('full'), 'day')} complete · {plural(count('partial'), 'day')} partial · {plural(count('missed'), 'day')} missed
          {pastPlanned > 0 && ` · ${Math.round((pastDone / pastPlanned) * 100)}% of tasks done`}
        </p>
      </section>

      <section className="card" aria-label="Last 7 days">
        <h2>Last 7 days</h2>
        <BarChart days={week} />
        <p className="muted" style={{ marginBottom: 0 }}>{overview.data.week.done} of {overview.data.week.planned} tasks done ({overview.data.week.completion_pct}%)</p>
      </section>

      <section className="card" aria-label="Achievements">
        <h2>Streak: {plural(streak, 'day')}</h2>
        <div className="row wrap">
          {STREAK_BADGES.map((b) => {
            const got = streak >= b.days;
            return (
              <div key={b.days} className="chip" style={{ opacity: got ? 1 : 0.55, padding: '6px 12px' }} aria-label={`${b.title}, ${b.days} day streak, ${got ? 'unlocked' : 'locked'}`}>
                <span aria-hidden="true">{got ? '★' : '☆'}</span> {b.title} · {b.days}
              </div>
            );
          })}
        </div>
      </section>

      <section className="card" aria-label="Habits">
        <h2>Habits</h2>
        {habits.error && <ErrorBanner message={habits.error} onRetry={() => void habits.reload()} />}
        {habits.data && habits.data.habits.length === 0 && <EmptyState title="No repeating tasks yet">Tasks that repeat show their streak here.</EmptyState>}
        {habits.data?.habits.map((h) => (
          <div className="task" key={h.task_id}>
            <div className="body">
              <div className="title">{h.title}</div>
              <div className="muted small">
                {h.current_streak > 0 ? `${plural(h.current_streak, 'day')} in a row` : 'No streak right now'} · best {h.best_streak}
                {h.rate_90 != null && ` · ${h.rate_90}% over 90 days`}
              </div>
            </div>
            <HabitDots habit={h} />
          </div>
        ))}
      </section>
    </>
  );
}
