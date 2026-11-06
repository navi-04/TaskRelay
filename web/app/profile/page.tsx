'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import Shell, { useMe } from '@/components/Shell';
import { api, errorMessage } from '@/lib/web/api';
import type { SettingsDto } from '@/lib/services/settings';

export default function ProfilePage() {
  return (
    <Shell>
      <h1>Profile</h1>
      <AiAccess />
      <Limits />
      <Account />
    </Shell>
  );
}

function AiAccess() {
  const { me, refresh } = useMe();
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [origin, setOrigin] = useState('');
  useEffect(() => setOrigin(location.origin), []);

  const link = `${origin}/api/ai?uid=${me.ai_access_id}`;
  const prompt =
    `Use my TaskRelay API to manage my tasks.\n` +
    `Read the manual first: ${link}\n` +
    `Follow its rules. Ask me before deleting anything or changing many tasks at once.`;

  const run = async (fn: () => Promise<unknown>, done?: string) => {
    setBusy(true);
    setError(null);
    setNote(null);
    try {
      await fn();
      await refresh();
      if (done) setNote(done);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };
  const copy = (text: string, what: string) =>
    navigator.clipboard.writeText(text).then(() => setNote(`${what} copied`), () => setError('Could not copy. Select the text and copy it manually.'));

  return (
    <section className="card" aria-labelledby="ai-h">
      <div className="spread">
        <h2 id="ai-h">Claude access</h2>
        <label className="row" style={{ margin: 0 }}>
          <input type="checkbox" checked={me.ai_access_enabled} disabled={busy}
            onChange={(e) => run(() => api('/me/ai-access', { method: 'PATCH', body: { enabled: e.target.checked } }))} />
          <span>{me.ai_access_enabled ? 'On' : 'Off'}</span>
        </label>
      </div>
      <p className="muted">
        Give this to Claude Desktop (or any assistant that can open links). It can read and change your tasks, nothing else.
        <strong> Treat it like a password</strong>: anyone who has it can read, add, change and delete your tasks.
      </p>
      {error && <div className="banner" role="alert">{error}</div>}
      {note && <p className="muted" role="status">{note}</p>}
      <label htmlFor="ai-id">Your AI access ID</label>
      <div className="row">
        <input id="ai-id" readOnly className="mono grow" value={me.ai_access_id} onFocus={(e) => e.currentTarget.select()} />
        <button disabled={busy} onClick={() => copy(me.ai_access_id, 'ID')}>Copy ID</button>
      </div>
      <div className="row wrap" style={{ marginTop: 12 }}>
        <button className="primary" disabled={busy || !me.ai_access_enabled} onClick={() => copy(prompt, 'Prompt')}>Copy prompt for Claude</button>
        <button className="danger" disabled={busy}
          onClick={() => confirm('Create a new ID? The current one stops working immediately.') && run(() => api('/me/ai-access/regenerate', { method: 'POST' }), 'New ID created. The old one no longer works.')}>
          Regenerate
        </button>
      </div>
      <p className="muted" style={{ marginBottom: 0 }}>
        {me.ai_last_used_at ? `Last used ${new Date(me.ai_last_used_at).toLocaleString()}.` : 'Not used yet.'} If you didn’t expect that, regenerate the ID.
      </p>
    </section>
  );
}

function Limits() {
  const [s, setS] = useState<SettingsDto | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    api<SettingsDto>('/settings').then(setS).catch((e) => setError(errorMessage(e)));
  }, []);

  async function save() {
    if (!s) return;
    setError(null);
    setSaved(false);
    try {
      setS(await api<SettingsDto>('/settings', {
        method: 'PATCH',
        body: { estimation_mode: s.estimation_mode, daily_time_limit_min: s.daily_time_limit_min, daily_count_limit: s.daily_count_limit },
      }));
      setSaved(true);
    } catch (e) {
      setError(errorMessage(e));
    }
  }

  return (
    <section className="card" aria-labelledby="lim-h">
      <h2 id="lim-h">Daily limit</h2>
      {error && <div className="banner" role="alert">{error}</div>}
      {!s ? <p className="muted">Loading…</p> : (
        <>
          <label htmlFor="mode">Measure my day by</label>
          <select id="mode" value={s.estimation_mode} onChange={(e) => setS({ ...s, estimation_mode: e.target.value as 'time' | 'count' })}>
            <option value="time">Time (minutes)</option>
            <option value="count">Number of tasks</option>
          </select>
          {s.estimation_mode === 'time' ? (
            <>
              <label htmlFor="tl">Daily time limit (minutes)</label>
              <input id="tl" type="number" min={15} max={1440} value={s.daily_time_limit_min} onChange={(e) => setS({ ...s, daily_time_limit_min: Number(e.target.value) })} />
            </>
          ) : (
            <>
              <label htmlFor="cl">Daily task limit</label>
              <input id="cl" type="number" min={1} max={100} value={s.daily_count_limit} onChange={(e) => setS({ ...s, daily_count_limit: Number(e.target.value) })} />
            </>
          )}
          <div className="row" style={{ marginTop: 12 }}>
            <button className="primary" onClick={save}>Save</button>
            {saved && <span className="muted" role="status">Saved</span>}
          </div>
        </>
      )}
    </section>
  );
}

function Account() {
  const router = useRouter();
  const { me } = useMe();
  const [error, setError] = useState<string | null>(null);

  const signOut = () => api('/auth/logout', { method: 'POST' }).catch(() => undefined).then(() => router.replace('/'));
  const wipe = () => {
    if (!confirm('Delete ALL your tasks? This cannot be undone.')) return;
    api('/me/data', { method: 'DELETE' }).then(() => alert('All tasks deleted.'), (e) => setError(errorMessage(e)));
  };

  return (
    <section className="card" aria-labelledby="acc-h">
      <h2 id="acc-h">Account</h2>
      {error && <div className="banner" role="alert">{error}</div>}
      <p className="muted">{me.email} · {me.timezone}</p>
      <div className="row wrap">
        <button onClick={signOut}>Sign out</button>
        <button className="danger" onClick={wipe}>Delete all my tasks</button>
      </div>
    </section>
  );
}
