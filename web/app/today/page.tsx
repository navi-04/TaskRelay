'use client';

import { useCallback, useEffect, useState, type FormEvent } from 'react';
import Shell from '@/components/Shell';
import { api, errorMessage } from '@/lib/web/api';
import type { LabelDto } from '@/lib/services/labels';
import type { SettingsDto } from '@/lib/services/settings';
import type { TaskDto } from '@/lib/services/tasks';
import type { DayView } from '@/lib/services/views';

interface StatsView {
  streak: number;
}

const shift = (date: string, n: number) => {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
};

const fmtMin = (m: number) => (m >= 60 ? `${Math.floor(m / 60)}h${m % 60 ? ` ${m % 60}m` : ''}` : `${m}m`);

export default function TodayPage() {
  return (
    <Shell>
      <Today />
    </Shell>
  );
}

function Today() {
  const [date, setDate] = useState<string | null>(null);
  const [view, setView] = useState<DayView | null>(null);
  const [priorities, setPriorities] = useState<LabelDto[]>([]);
  const [settings, setSettings] = useState<SettingsDto | null>(null);
  const [streak, setStreak] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);

  const load = useCallback(async (d: string | null) => {
    try {
      const v = await api<DayView>(`/tasks${d ? `?date=${d}` : ''}`);
      setView(v);
      setDate(v.date);
      setError(null);
      api<StatsView>('/stats').then((s) => setStreak(s.streak), () => undefined);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, []);

  useEffect(() => {
    load(null);
    api<{ priorities: LabelDto[] }>('/labels').then((l) => setPriorities(l.priorities), () => undefined);
    api<SettingsDto>('/settings').then(setSettings, () => undefined);
  }, [load]);

  /** Run a mutation, then reload; failures stay visible instead of looking like success. */
  async function act(fn: () => Promise<unknown>) {
    setBusy(true);
    try {
      await fn();
      await load(date);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  const toggle = (t: TaskDto) =>
    act(() => api(`/tasks/${t.id}/days/${t.date}`, { method: 'PUT', body: { status: t.status === 'done' ? 'open' : 'done' } }));

  const remove = (t: TaskDto, scope: string) => {
    setDeleting(null);
    return act(() => api(`/tasks/${t.id}?scope=${encodeURIComponent(scope)}`, { method: 'DELETE' }));
  };

  const moveOverdue = () =>
    view?.overdue && act(() => api('/tasks/move', { method: 'POST', body: { ids: view.overdue!.items.map((t) => t.id), to: view.today } }));

  if (!view) return error ? <div className="banner" role="alert">{error} <button onClick={() => load(date)}>Retry</button></div> : <p className="muted">Loading…</p>;

  const isToday = view.date === view.today;
  const mode = settings?.estimation_mode ?? 'time';
  const used = mode === 'time' ? view.summary.planned_min : view.summary.planned;
  const limit = settings ? (mode === 'time' ? settings.daily_time_limit_min : settings.daily_count_limit) : 0;
  const over = limit > 0 && used > limit;

  return (
    <>
      <div className="spread" style={{ marginBottom: 12 }}>
        <div className="row">
          <button aria-label="Previous day" onClick={() => load(shift(view.date, -1))}>‹</button>
          <input type="date" aria-label="Day" value={view.date} onChange={(e) => e.target.value && load(e.target.value)} style={{ width: 'auto' }} />
          <button aria-label="Next day" onClick={() => load(shift(view.date, 1))}>›</button>
        </div>
        {!isToday && <button onClick={() => load(view.today)}>Today</button>}
      </div>

      {error && <div className="banner" role="alert">{error}</div>}

      <section className="card" aria-label="Day summary">
        <div className="spread">
          <strong>{view.summary.done} of {view.summary.planned} done</strong>
          <span className="muted">{streak > 0 ? `🔥 ${streak}-day streak` : 'No streak yet'}</span>
        </div>
        {limit > 0 && (
          <>
            <div className="bar-track" style={{ margin: '10px 0 4px' }} role="progressbar" aria-valuenow={used} aria-valuemin={0} aria-valuemax={limit}>
              <div className={`bar-fill${over ? ' over' : ''}`} style={{ width: `${Math.min(100, (used / limit) * 100)}%` }} />
            </div>
            <span className={over ? 'banner' : 'muted'} style={over ? { display: 'inline-block', padding: '2px 8px', margin: 0 } : undefined}>
              {mode === 'time' ? `${fmtMin(used)} planned of ${fmtMin(limit)}` : `${used} of ${limit} tasks planned`}{over ? ' — over your limit' : ''}
            </span>
          </>
        )}
      </section>

      {view.overdue && view.overdue.count > 0 && (
        <section className="card" aria-label="Overdue">
          <div className="spread">
            <h2 style={{ margin: 0 }}>Overdue ({view.overdue.count})</h2>
            <button disabled={busy} onClick={moveOverdue}>Move {view.overdue.items.length} to today</button>
          </div>
          {view.overdue.items.map((t) => (
            <div className="task" key={t.id}>
              <div className="grow">
                <div className="title">{t.title}</div>
                <div className="muted">was due {t.due_date} · {fmtMin(t.duration_min)}</div>
              </div>
            </div>
          ))}
        </section>
      )}

      <section className="card" aria-label="Tasks">
        {view.tasks.length === 0 ? (
          <p className="empty">Nothing planned for this day.</p>
        ) : (
          view.tasks.map((t) => (
            <div className={`task${t.status === 'done' ? ' done' : ''}`} key={t.id}>
              <input className="check" type="checkbox" checked={t.status === 'done'} disabled={busy} aria-label={`Mark "${t.title}" ${t.status === 'done' ? 'not done' : 'done'}`} onChange={() => toggle(t)} />
              <div className="grow">
                <div className="title">{t.title}</div>
                <div>
                  <span className="chip">{fmtMin(t.duration_min)}</span>
                  {t.alarm_time && <span className="chip">⏰ {t.alarm_time}</span>}
                  {t.recur === 'daily' && <span className="chip">repeats daily</span>}
                  {priorities.find((p) => p.id === t.priority_id) && <span className="chip">{priorities.find((p) => p.id === t.priority_id)!.label}</span>}
                </div>
                {deleting === t.id && (
                  <div className="row wrap" style={{ marginTop: 8 }}>
                    <button className="danger" onClick={() => remove(t, `day:${t.date}`)}>Just this day</button>
                    <button className="danger" onClick={() => remove(t, `from:${t.date}`)}>This and following days</button>
                    <button className="danger" onClick={() => remove(t, 'all')}>Whole series</button>
                    <button onClick={() => setDeleting(null)}>Cancel</button>
                  </div>
                )}
              </div>
              <button className="link" aria-label={`Delete "${t.title}"`} disabled={busy}
                onClick={() => (t.recur === 'daily' ? setDeleting(t.id) : confirm(`Delete "${t.title}"?`) && remove(t, 'all'))}>✕</button>
            </div>
          ))
        )}
      </section>

      <AddTask date={view.date} priorities={priorities} busy={busy} onAdd={(body) => act(() => api('/tasks', { method: 'POST', body }))} />
    </>
  );
}

function AddTask({ date, priorities, busy, onAdd }: { date: string; priorities: LabelDto[]; busy: boolean; onAdd: (body: Record<string, unknown>) => Promise<void> }) {
  const [title, setTitle] = useState('');
  const [minutes, setMinutes] = useState(30);
  const [priority, setPriority] = useState('');
  const [time, setTime] = useState('');
  const [daily, setDaily] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    await onAdd({
      id: crypto.randomUUID(), // client-generated, so a retried request can't create a duplicate
      title: title.trim(),
      due_date: date,
      duration_min: minutes,
      priority_id: priority || null,
      alarm_time: time || null,
      recur: daily ? 'daily' : 'none',
    });
    setTitle('');
  }

  return (
    <form className="card" onSubmit={submit} aria-label="Add a task">
      <div className="row">
        <input aria-label="Task title" className="grow" placeholder="Add a task…" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
        <button className="primary" disabled={busy || !title.trim()}>Add</button>
      </div>
      <div className="row wrap" style={{ marginTop: 8 }}>
        <label className="row muted" style={{ margin: 0 }}>Minutes
          <input type="number" min={1} max={1440} value={minutes} onChange={(e) => setMinutes(Number(e.target.value))} style={{ width: 80 }} />
        </label>
        <select aria-label="Priority" value={priority} onChange={(e) => setPriority(e.target.value)} style={{ width: 'auto' }}>
          <option value="">Priority</option>
          {priorities.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
        <input type="time" aria-label="Alarm time" value={time} onChange={(e) => setTime(e.target.value)} style={{ width: 'auto' }} />
        <label className="row muted" style={{ margin: 0 }}><input type="checkbox" checked={daily} onChange={(e) => setDaily(e.target.checked)} /> Repeat daily</label>
      </div>
    </form>
  );
}
