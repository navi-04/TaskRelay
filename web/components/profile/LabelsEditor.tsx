'use client';

import { useState, type FormEvent } from 'react';
import { useAsk, useToast } from '@/components/Feedback';
import { ErrorBanner, Skeleton } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { useApi } from '@/lib/web/hooks';
import type { LabelDto } from '@/lib/services/labels';

function LabelRow({ label, busy, onRename, onDelete }: { label: LabelDto; busy: boolean; onRename: (name: string) => void; onDelete: () => void }) {
  const [name, setName] = useState(label.label);
  const commit = () => {
    const next = name.trim();
    if (next && next !== label.label) onRename(next);
    else setName(label.label);
  };
  return (
    <div className="row" style={{ marginBottom: 8 }}>
      <input aria-label={`Name of ${label.label}`} className="grow" value={name} maxLength={40} disabled={busy} onChange={(e) => setName(e.target.value)} onBlur={commit} onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()} />
      <button className="icon" aria-label={`Delete ${label.label}`} disabled={busy} onClick={onDelete}>✕</button>
    </div>
  );
}

/** Rename, add and delete task types and priorities. Deleting one detaches it from tasks; the last of a kind stays. */
export default function LabelsEditor() {
  const labels = useApi<{ types: LabelDto[]; priorities: LabelDto[] }>('/labels');
  const toast = useToast();
  const ask = useAsk();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [kind, setKind] = useState<'type' | 'priority'>('priority');
  const [name, setName] = useState('');

  async function act(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await labels.reload();
    } catch (e) {
      setError(errorMessage(e));
      await labels.reload(); // show what the server really has
    } finally {
      setBusy(false);
    }
  }

  async function remove(l: LabelDto) {
    const choice = await ask({ title: `Delete “${l.label}”?`, message: 'Tasks that use it keep working; they just lose this label.', choices: [{ id: 'yes', label: 'Delete', tone: 'danger' }] });
    if (choice) await act(async () => { await api(`/labels/${l.id}`, { method: 'DELETE' }); toast(`Deleted “${l.label}”`); });
  }

  async function add(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    await act(async () => { await api('/labels', { method: 'POST', body: { kind, label: name.trim() } }); setName(''); });
  }

  const group = (title: string, items: LabelDto[]) => (
    <div>
      <h3>{title}</h3>
      {items.map((l) => (
        <LabelRow key={`${l.id}:${l.label}`} label={l} busy={busy} onRename={(label) => void act(() => api(`/labels/${l.id}`, { method: 'PATCH', body: { label } }))} onDelete={() => void remove(l)} />
      ))}
    </div>
  );

  return (
    <section className="card" aria-labelledby="labels-h">
      <h2 id="labels-h">Types &amp; priorities</h2>
      {error && <ErrorBanner message={error} />}
      {labels.error && !labels.data && <ErrorBanner message={labels.error} onRetry={() => void labels.reload()} />}
      {!labels.data ? (labels.error ? null : <Skeleton rows={3} />) : (
        <>
          {group('Priorities', labels.data.priorities)}
          {group('Types', labels.data.types)}
          <form className="row wrap" onSubmit={add} style={{ marginTop: 12 }} aria-label="Add a type or priority">
            <select aria-label="Kind" value={kind} style={{ width: 'auto' }} onChange={(e) => setKind(e.target.value as 'type' | 'priority')}>
              <option value="priority">Priority</option>
              <option value="type">Type</option>
            </select>
            <input aria-label="New name" className="grow" placeholder="New name" maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
            <button className="primary" disabled={busy || !name.trim()}>Add</button>
          </form>
        </>
      )}
    </section>
  );
}
