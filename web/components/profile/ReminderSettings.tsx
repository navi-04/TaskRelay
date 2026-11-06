'use client';

import { useEffect, useState } from 'react';
import { ErrorBanner, Skeleton } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { pad2 } from '@/lib/web/format';
import type { SettingsDto } from '@/lib/services/settings';

const hm = (h: number, m: number) => `${pad2(h)}:${pad2(m)}`;
const parseHm = (v: string): [number, number] => [Number(v.slice(0, 2)), Number(v.slice(3, 5))];

/** Daily limit (time or task count) and the reminders. Saved explicitly; the server value is the source of truth. */
export default function ReminderSettings() {
  const [saved, setSaved] = useState<SettingsDto | null>(null);
  const [s, setS] = useState<SettingsDto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const load = () =>
    api<SettingsDto>('/settings').then((d) => { setSaved(d); setS(d); }, (e) => setError(errorMessage(e)));
  useEffect(() => { void load(); }, []);

  if (!s || !saved) return <section className="card">{error ? <ErrorBanner message={error} onRetry={() => void load()} /> : <Skeleton rows={3} />}</section>;

  const dirty = (Object.keys(s) as Array<keyof SettingsDto>).filter((k) => s[k] !== saved[k]);
  const limitOk = s.daily_time_limit_min >= 15 && s.daily_time_limit_min <= 1440 && s.daily_count_limit >= 1 && s.daily_count_limit <= 100;

  async function save() {
    if (!s || !saved) return;
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      const patch = Object.fromEntries(dirty.map((k) => [k, s[k]]));
      const next = await api<SettingsDto>('/settings', { method: 'PATCH', body: patch });
      setSaved(next);
      setS(next);
      setNote('Saved');
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }

  const toggle = (key: 'daily_reminder_on' | 'end_of_day_on' | 'carry_over_alerts', label: string) => (
    <label className="row" style={{ margin: '8px 0', color: 'var(--text)' }}>
      <input type="checkbox" checked={s[key]} onChange={(e) => setS({ ...s, [key]: e.target.checked })} />
      {label}
    </label>
  );

  return (
    <section className="card" aria-labelledby="rem-h">
      <h2 id="rem-h">Daily limit &amp; reminders</h2>
      {error && <ErrorBanner message={error} />}

      <label htmlFor="mode">Measure my day by</label>
      <select id="mode" value={s.estimation_mode} onChange={(e) => setS({ ...s, estimation_mode: e.target.value as 'time' | 'count' })}>
        <option value="time">Time (minutes)</option>
        <option value="count">Number of tasks</option>
      </select>
      {s.estimation_mode === 'time' ? (
        <>
          <label htmlFor="tl">Daily time limit (minutes, 15–1440)</label>
          <input id="tl" type="number" inputMode="numeric" min={15} max={1440} value={s.daily_time_limit_min} onChange={(e) => setS({ ...s, daily_time_limit_min: Number(e.target.value) })} />
        </>
      ) : (
        <>
          <label htmlFor="cl">Daily task limit (1–100)</label>
          <input id="cl" type="number" inputMode="numeric" min={1} max={100} value={s.daily_count_limit} onChange={(e) => setS({ ...s, daily_count_limit: Number(e.target.value) })} />
        </>
      )}

      <h3>Reminders on your phone</h3>
      {toggle('daily_reminder_on', 'Morning reminder with my Top 3')}
      {s.daily_reminder_on && (
        <input aria-label="Morning reminder time" type="time" value={hm(s.daily_reminder_hour, s.daily_reminder_min)} style={{ width: 'auto' }}
          onChange={(e) => { if (e.target.value) { const [h, m] = parseHm(e.target.value); setS({ ...s, daily_reminder_hour: h, daily_reminder_min: m }); } }} />
      )}
      {toggle('end_of_day_on', 'End-of-day summary')}
      {s.end_of_day_on && (
        <input aria-label="End-of-day time" type="time" value={hm(s.end_of_day_hour, s.end_of_day_min)} style={{ width: 'auto' }}
          onChange={(e) => { if (e.target.value) { const [h, m] = parseHm(e.target.value); setS({ ...s, end_of_day_hour: h, end_of_day_min: m }); } }} />
      )}
      {toggle('carry_over_alerts', 'Mention overdue tasks in the morning reminder')}
      <p className="muted small">Reminders are delivered by the Android app.</p>

      <div className="row" style={{ marginTop: 12 }}>
        <button className="primary" disabled={busy || dirty.length === 0 || !limitOk} onClick={save}>{busy ? 'Saving…' : 'Save'}</button>
        {note && dirty.length === 0 && <span className="muted" role="status">{note}</span>}
        {dirty.length > 0 && <button className="link" onClick={() => setS(saved)}>Discard changes</button>}
      </div>
    </section>
  );
}
