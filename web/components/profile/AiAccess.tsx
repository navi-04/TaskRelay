'use client';

import { useEffect, useState } from 'react';
import { useToast } from '@/components/Feedback';
import { useMe } from '@/components/Shell';
import { ErrorBanner } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { useApi } from '@/lib/web/hooks';
import type { ActivityItem } from '@/lib/services/activity';
import { useAsk } from '@/components/Feedback';

const PROMPTS = [
  { title: 'Plan my day', text: 'Look at my TaskRelay overview and help me plan today. Suggest a realistic Top 3, point out anything over my daily limit, and ask me before changing anything.' },
  { title: 'Pick my Top 3', text: "Read today's tasks and propose my Top 3: the most important ones I can realistically finish. If I agree, set them as my Top 3." },
  { title: 'Sort out overdue', text: 'List my overdue tasks and, for each, suggest whether to do it today, move it to another day, or delete it. Ask me before moving or deleting anything.' },
  { title: 'Weekly review', text: 'Read my weekly review and my habits. Tell me what went well and what to improve, then help me plan next week.' },
  { title: 'Set up a routine', text: 'Help me set up a weekly routine as repeating tasks on specific weekdays. Ask me what and when, then create them and tell me exactly what you added.' },
] as const;

const KIND_WORD: Record<string, string> = { created: 'added', updated: 'changed', deleted: 'deleted', completed: 'completed', rescheduled: 'moved', restored: 'restored' };

function ago(iso: string): string {
  const mins = Math.round((Date.now() - Date.parse(iso)) / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 1440) return `${Math.round(mins / 60)} h ago`;
  return `${Math.round(mins / 1440)} d ago`;
}

export default function AiAccess() {
  const { me, refresh } = useMe();
  const toast = useToast();
  const ask = useAsk();
  const feed = useApi<{ items: ActivityItem[] }>('/activity?limit=8');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [origin, setOrigin] = useState('');
  useEffect(() => setOrigin(location.origin), []);

  const link = `${origin}/api/ai?uid=${me.ai_access_id}`;

  async function run(fn: () => Promise<unknown>, done?: string) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await refresh();
      if (done) toast(done);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  const copy = (text: string, what: string) =>
    navigator.clipboard.writeText(text).then(() => toast(`${what} copied`), () => setError('Could not copy. Select the text and copy it manually.'));

  async function regenerate() {
    const choice = await ask({ title: 'Create a new ID?', message: 'The current one stops working immediately. Anything using it (for example a Claude chat) will need the new one.', choices: [{ id: 'yes', label: 'Create new ID', tone: 'danger' }] });
    if (choice) await run(() => api('/me/ai-access/regenerate', { method: 'POST' }), 'New ID created. The old one no longer works.');
  }

  async function restore(item: ActivityItem) {
    try {
      await api(`/tasks/${item.task_id}/restore`, { method: 'POST' });
      toast(`Restored “${item.title}”`);
      await feed.reload();
    } catch (e) {
      setError(errorMessage(e));
    }
  }

  return (
    <>
      <section className="card" aria-labelledby="ai-h">
        <div className="spread">
          <h2 id="ai-h" style={{ margin: 0 }}>Claude access</h2>
          <label className="row" style={{ margin: 0, color: 'var(--text)' }}>
            <input type="checkbox" checked={me.ai_access_enabled} disabled={busy} onChange={(e) => run(() => api('/me/ai-access', { method: 'PATCH', body: { enabled: e.target.checked } }))} />
            {me.ai_access_enabled ? 'On' : 'Off'}
          </label>
        </div>
        <p className="muted">
          Give this to Claude (or any assistant that can open links). It can read and change your tasks, nothing else.
          <strong> Treat it like a password</strong>: anyone who has it can read, add, change and delete your tasks.
        </p>
        {error && <ErrorBanner message={error} />}
        <label htmlFor="ai-id">Your AI access ID</label>
        <div className="row">
          <input id="ai-id" readOnly className="mono grow" value={me.ai_access_id} onFocus={(e) => e.currentTarget.select()} />
          <button disabled={busy} onClick={() => copy(me.ai_access_id, 'ID')}>Copy ID</button>
        </div>
        <div className="row wrap" style={{ marginTop: 12 }}>
          <button className="primary" disabled={busy || !me.ai_access_enabled} onClick={() => copy(`Use my TaskRelay API to manage my tasks.\nRead the manual first: ${link}\nFollow its rules. Ask me before deleting anything or changing many tasks at once.`, 'Prompt')}>Copy prompt for Claude</button>
          <button className="danger" disabled={busy} onClick={regenerate}>Regenerate</button>
        </div>
        <p className="muted small" style={{ marginBottom: 0 }}>
          {me.ai_last_used_at ? `Last used ${new Date(me.ai_last_used_at).toLocaleString()}.` : 'Not used yet.'} If you didn’t expect that, regenerate the ID.
        </p>
      </section>

      <section className="card" aria-labelledby="prompts-h">
        <h2 id="prompts-h">Things to ask Claude</h2>
        <p className="muted">Each button copies a ready-made request with your link attached.</p>
        <div className="row wrap">
          {PROMPTS.map((p) => (
            <button key={p.title} disabled={!me.ai_access_enabled} onClick={() => copy(`${p.text}\n\nMy TaskRelay manual: ${link}`, `“${p.title}”`)}>{p.title}</button>
          ))}
        </div>
        {!me.ai_access_enabled && <p className="muted small">Turn Claude access on to use these.</p>}
      </section>

      <section className="card" aria-labelledby="activity-h">
        <h2 id="activity-h">Recent changes by Claude</h2>
        {feed.error && <ErrorBanner message={feed.error} onRetry={() => void feed.reload()} />}
        {feed.data && feed.data.items.length === 0 && <p className="muted">Nothing yet. When Claude changes your tasks, it shows up here.</p>}
        {feed.data?.items.map((i) => (
          <div className="task" key={i.id}>
            <div className="body">
              <div className="title">{i.title}</div>
              <div className="muted small">{KIND_WORD[i.kind] ?? i.kind}{i.date ? ` · ${i.date}` : ''} · {ago(i.at)}</div>
            </div>
            {i.kind === 'deleted' && <button onClick={() => void restore(i)}>Restore</button>}
          </div>
        ))}
      </section>
    </>
  );
}
