'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useState, type FormEvent } from 'react';
import { useAsk, useToast } from '@/components/Feedback';
import Shell from '@/components/Shell';
import TaskForm from '@/components/TaskForm';
import TaskRow from '@/components/TaskRow';
import { EmptyState, ErrorBanner, ProgressRing, Skeleton } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { fmtDay, fmtMin, plural, shiftDate } from '@/lib/web/format';
import { useApi } from '@/lib/web/hooks';
import type { HabitDto } from '@/lib/services/habits';
import type { LabelDto } from '@/lib/services/labels';
import type { SettingsDto } from '@/lib/services/settings';
import type { TaskDto } from '@/lib/services/tasks';
import type { DayView } from '@/lib/services/views';

export default function TodayPage() {
  return (
    <Shell>
      <Suspense fallback={<Skeleton />}>
        <Today />
      </Suspense>
    </Shell>
  );
}

function Today() {
  const router = useRouter();
  const params = useSearchParams();
  const toast = useToast();
  const ask = useAsk();

  const requested = params.get('date');
  const date = requested && /^\d{4}-\d{2}-\d{2}$/.test(requested) ? requested : null;
  const day = useApi<DayView>(`/tasks${date ? `?date=${date}` : ''}`);
  const labels = useApi<{ types: LabelDto[]; priorities: LabelDto[] }>('/labels');
  const settings = useApi<SettingsDto>('/settings');
  const stats = useApi<{ streak: number }>('/stats');
  const habits = useApi<{ habits: HabitDto[] }>('/habits?days=7');

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<{ task?: TaskDto } | null>(null);
  const [quick, setQuick] = useState('');

  const view = day.data;
  const refresh = () => Promise.all([day.reload(), stats.reload(), habits.reload()]).then(() => undefined);

  /** Run a change; any failure stays on screen instead of looking like success. */
  async function act(fn: () => Promise<unknown>): Promise<boolean> {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await refresh();
      return true;
    } catch (e) {
      setError(errorMessage(e));
      return false;
    } finally {
      setBusy(false);
    }
  }

  if (!view) {
    return day.error ? <ErrorBanner message={day.error} onRetry={() => void day.reload()} /> : <Skeleton rows={4} />;
  }

  const go = (d: string) => router.push(d === view.today ? '/today' : `/today?date=${d}`);
  const priorities = labels.data?.priorities ?? [];
  const priorityOf = (id: string | null) => priorities.find((p) => p.id === id);
  const habitOf = (id: string) => habits.data?.habits.find((h) => h.task_id === id);

  const topTasks = view.tasks.filter((t) => t.top_position != null).sort((a, b) => a.top_position! - b.top_position!);
  const rest = view.tasks.filter((t) => t.top_position == null);
  const { planned, done, planned_min } = view.summary;
  const mode = settings.data?.estimation_mode ?? 'time';
  const used = mode === 'time' ? planned_min : planned;
  const limit = settings.data ? (mode === 'time' ? settings.data.daily_time_limit_min : settings.data.daily_count_limit) : 0;
  const over = limit > 0 && used > limit;
  const isToday = view.date === view.today;

  // ── actions ──────────────────────────────────────────────────────────────────────────────────
  const toggle = (t: TaskDto) =>
    act(() => api(`/tasks/${t.id}/days/${t.date}`, { method: 'PUT', body: { status: t.status === 'done' ? 'open' : 'done' } }));

  const star = (t: TaskDto) => {
    const next = t.top_position != null ? view.top.filter((id) => id !== t.id) : [...view.top, t.id];
    return act(() => api(`/days/${view.date}/top`, { method: 'PUT', body: { task_ids: next } }));
  };

  async function remove(t: TaskDto) {
    const recurring = t.recur !== 'none';
    const choice = await ask(
      recurring
        ? { title: `Delete “${t.title}”?`, message: 'This task repeats. What should be deleted?', choices: [
            { id: `day:${view!.date}`, label: `Just ${fmtDay(view!.date)}`, tone: 'danger' },
            { id: `from:${view!.date}`, label: 'This and all following days', tone: 'danger' },
            { id: 'all', label: 'The whole series', tone: 'danger' },
          ] }
        : { title: `Delete “${t.title}”?`, choices: [{ id: 'all', label: 'Delete', tone: 'danger' }] },
    );
    if (!choice) return;

    // How to undo each kind of delete (all of them are plain API calls, so undo survives a page reload within the toast)
    const wholeTask = choice === 'all' || !recurring || (choice.startsWith('from:') && choice.slice(5) <= t.due_date);
    const undo = async () => {
      await act(() => {
        if (wholeTask) return api(`/tasks/${t.id}/restore`, { method: 'POST' });
        if (choice.startsWith('day:')) return api(`/tasks/${t.id}/days/${choice.slice(4)}`, { method: 'PUT', body: { status: 'open' } });
        return api(`/tasks/${t.id}`, { method: 'PATCH', body: { recur_until: t.recur_until } }); // from:D -> put the old end date back
      });
    };
    const ok = await act(() => api(`/tasks/${t.id}?scope=${encodeURIComponent(choice)}`, { method: 'DELETE' }));
    if (ok) toast(wholeTask ? `Deleted “${t.title}”` : choice.startsWith('day:') ? `Skipped ${fmtDay(view!.date)}` : 'Series ended', { actionLabel: 'Undo', onAction: undo });
  }

  async function moveOverdue() {
    const items = view!.overdue?.items ?? [];
    if (items.length === 0) return;
    const byDay = new Map<string, string[]>();
    for (const t of items) byDay.set(t.due_date, [...(byDay.get(t.due_date) ?? []), t.id]);
    const ok = await act(() => api('/tasks/move', { method: 'POST', body: { ids: items.map((t) => t.id), to: view!.today } }));
    if (ok) {
      toast(`Moved ${plural(items.length, 'task')} to today`, {
        actionLabel: 'Undo',
        onAction: async () => {
          await act(async () => {
            for (const [from, ids] of byDay) await api('/tasks/move', { method: 'POST', body: { ids, to: from } });
          });
        },
      });
    }
  }

  async function quickAdd(e: FormEvent) {
    e.preventDefault();
    const title = quick.trim();
    if (!title) return;
    // client-generated id: a retried request can't create a duplicate
    const ok = await act(() => api('/tasks', { method: 'POST', body: { id: crypto.randomUUID(), title, due_date: view!.date, duration_min: 30 } }));
    if (ok) setQuick('');
  }

  const row = (t: TaskDto) => (
    <TaskRow
      key={t.id}
      task={t}
      priority={priorityOf(t.priority_id)}
      habit={habitOf(t.id)}
      busy={busy}
      canStar={view.top.length < 3}
      onToggle={toggle}
      onEdit={(x) => setForm({ task: x })}
      onDelete={remove}
      onStar={star}
    />
  );

  return (
    <div style={{ opacity: day.loading ? 0.6 : 1, transition: 'opacity .15s' }} aria-busy={day.loading}>
      <div className="spread" style={{ marginBottom: 12 }}>
        <div className="row">
          <button className="icon" aria-label="Previous day" onClick={() => go(shiftDate(view.date, -1))}>‹</button>
          <h1 style={{ margin: 0 }}>{isToday ? 'Today' : fmtDay(view.date)}</h1>
          <button className="icon" aria-label="Next day" onClick={() => go(shiftDate(view.date, 1))}>›</button>
        </div>
        <div className="row">
          <label className="sr-only" htmlFor="jump">Jump to date</label>
          <input id="jump" type="date" value={view.date} style={{ width: 'auto' }} onChange={(e) => e.target.value && go(e.target.value)} />
          {!isToday && <button onClick={() => go(view.today)}>Today</button>}
        </div>
      </div>

      {error && <ErrorBanner message={error} />}
      {day.error && <ErrorBanner message={`Couldn’t refresh: ${day.error}`} onRetry={() => void day.reload()} />}

      <section className="card" aria-label="Day summary">
        <div className="row">
          <ProgressRing percent={planned === 0 ? 0 : (done / planned) * 100} label={`${done}/${planned}`} />
          <div className="grow">
            <strong>{planned === 0 ? 'Nothing planned' : done === planned ? 'All done!' : `${plural(planned - done, 'task')} to go`}</strong>
            <div className="muted">{(stats.data?.streak ?? 0) > 0 ? `${plural(stats.data!.streak, 'day')} in a row` : 'Finish a day to start a streak'}</div>
          </div>
        </div>
        {limit > 0 && (
          <div style={{ marginTop: 12 }}>
            <div className="bar-track" role="progressbar" aria-valuenow={used} aria-valuemin={0} aria-valuemax={limit} aria-label="Planned against your daily limit">
              <div className={`bar-fill${over ? ' over' : ''}`} style={{ width: `${Math.min(100, (used / limit) * 100)}%` }} />
            </div>
            <div className="small" style={{ marginTop: 4, color: over ? 'var(--text)' : 'var(--muted)', fontWeight: over ? 800 : 400 }}>
              {mode === 'time' ? `${fmtMin(used)} planned of ${fmtMin(limit)}` : `${used} of ${limit} tasks planned`}
              {over && ' — over your daily limit'}
            </div>
          </div>
        )}
      </section>

      {view.overdue && view.overdue.count > 0 && (
        <section className="card" aria-label="Overdue tasks">
          <div className="spread">
            <h2 style={{ margin: 0 }}>Overdue · {view.overdue.count}</h2>
            <button disabled={busy} onClick={moveOverdue}>Move {view.overdue.items.length === view.overdue.count ? 'all' : `${view.overdue.items.length}`} to today</button>
          </div>
          {view.overdue.items.map((t) => (
            <div className="task" key={t.id}>
              <div className="body">
                <div className="title">{t.title}</div>
                <div className="muted small">was due {fmtDay(t.due_date)} · {fmtMin(t.duration_min)}</div>
              </div>
              <button className="icon" aria-label={`Edit: ${t.title}`} disabled={busy} onClick={() => setForm({ task: t })}>✎</button>
              <button className="icon" aria-label={`Delete: ${t.title}`} disabled={busy} onClick={() => remove(t)}>✕</button>
            </div>
          ))}
          {view.overdue.count > view.overdue.items.length && <p className="muted small">Showing the {view.overdue.items.length} most recent of {view.overdue.count}.</p>}
        </section>
      )}

      {topTasks.length > 0 && (
        <section className="card" aria-label="Top 3">
          <h2>★ Top 3 for {isToday ? 'today' : fmtDay(view.date)}</h2>
          {topTasks.map(row)}
        </section>
      )}

      <section className="card" aria-label="Tasks">
        {topTasks.length > 0 && <h2>Other tasks</h2>}
        {view.tasks.length === 0 ? (
          <EmptyState title={isToday ? 'A clear day' : 'Nothing planned for this day'}>Add a task below to get started.</EmptyState>
        ) : rest.length === 0 ? (
          <p className="muted">Everything is in your Top 3.</p>
        ) : (
          rest.map(row)
        )}
      </section>

      <form className="card" onSubmit={quickAdd} aria-label="Add a task">
        <div className="row">
          <label className="sr-only" htmlFor="quick">Task title</label>
          <input id="quick" className="grow" placeholder={`Add a task for ${isToday ? 'today' : fmtDay(view.date)}…`} maxLength={200} value={quick} onChange={(e) => setQuick(e.target.value)} />
          <button className="primary" disabled={busy || !quick.trim()}>Add</button>
        </div>
        <div className="row" style={{ marginTop: 4 }}>
          <button type="button" className="link" onClick={() => setForm({})}>More options (time, reminder, repeat…)</button>
        </div>
      </form>

      {form && (
        <TaskForm
          task={form.task}
          date={view.date}
          today={view.today}
          types={labels.data?.types ?? []}
          priorities={priorities}
          onClose={() => setForm(null)}
          onSaved={() => {
            setForm(null);
            void refresh();
          }}
        />
      )}
    </div>
  );
}
