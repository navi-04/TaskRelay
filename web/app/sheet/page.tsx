'use client';

import { useEffect, useRef, useState } from 'react';
import { useToast } from '@/components/Feedback';
import Shell from '@/components/Shell';
import SheetTable, { type ToggleTarget } from '@/components/sheet/SheetTable';
import { EmptyState, ErrorBanner, Skeleton } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { monthStart } from '@/lib/web/calendar';
import { fmtMonth } from '@/lib/web/format';
import { useApi } from '@/lib/web/hooks';
import { dayName, isEmptyMonth, nextMonth, nextStatus, prevMonth, SHEET_FILTERS, sheetPath, withStatus, type SheetFilter } from '@/lib/web/sheet';
import type { CellState, SheetView } from '@/lib/services/sheet';

export default function SheetPage() {
  return (
    <Shell>
      <h1>Sheet</h1>
      <Sheet />
    </Shell>
  );
}

function Sheet() {
  const toast = useToast();
  // null = the current month, as the server sees it (its default window); the first response tells us which month that is.
  const [month, setMonth] = useState<string | null>(null);
  const [filter, setFilter] = useState<SheetFilter>('all');
  const [scrollSignal, setScrollSignal] = useState(0);
  const { data, error, reload } = useApi<SheetView>(sheetPath(month));

  // What is on screen: the loaded data plus any taps still waiting for the server (optimistic updates).
  const [local, setLocal] = useState<SheetView>();
  const inFlight = useRef(new Set<string>()); // "taskId|date" with a request running: a second tap on it is ignored
  const pending = useRef(0);
  const changed = useRef(false);
  const reloadRef = useRef(reload); // always the reload for the month on screen, even if a tap finishes after a month change
  useEffect(() => {
    reloadRef.current = reload;
  }, [reload]);

  useEffect(() => {
    if (!data) return;
    // A reload that lands while taps are still in flight must not undo them; the last tap to finish reloads again.
    setLocal((prev) => (pending.current === 0 || !prev || prev.from !== data.from ? data : prev));
  }, [data]);

  const viewMonth = month ?? (data ? monthStart(data.today) : null);
  const view = local && viewMonth && local.from === viewMonth ? local : undefined;

  async function toggle(t: ToggleTarget, current: CellState) {
    const key = `${t.id}|${t.date}`;
    if (inFlight.current.has(key)) return;
    inFlight.current.add(key);
    pending.current++;
    const next = nextStatus(current);
    setLocal((v) => v && withStatus(v, t.id, t.date, next));
    try {
      await api(`/tasks/${t.id}/days/${t.date}`, { method: 'PUT', body: { status: next } });
      changed.current = true;
    } catch (e) {
      setLocal((v) => v && withStatus(v, t.id, t.date, current));
      toast(`Could not update “${t.title}” on ${dayName(t)}. ${errorMessage(e)}`);
    } finally {
      inFlight.current.delete(key);
      pending.current--;
    }
    // Refresh once everything has settled, so the totals come from the server.
    if (pending.current === 0 && changed.current) {
      changed.current = false;
      await reloadRef.current();
    }
  }

  const goToday = () => {
    setMonth(null);
    setScrollSignal((n) => n + 1);
  };

  return (
    <div className="sheet-page">
      {viewMonth && (
        <div className="sheet-bar">
          <div className="sheet-nav">
            <button className="icon" aria-label="Previous month" onClick={() => setMonth(prevMonth(viewMonth))}>{'‹'}</button>
            <h2 aria-live="polite">{fmtMonth(viewMonth)}</h2>
            <button className="icon" aria-label="Next month" onClick={() => setMonth(nextMonth(viewMonth))}>{'›'}</button>
          </div>
          <div className="sheet-filters">
            <button onClick={goToday}>Today</button>
            <label htmlFor="sheet-filter" className="sr-only">Show</label>
            <select id="sheet-filter" value={filter} onChange={(e) => setFilter(e.target.value as SheetFilter)}>
              {SHEET_FILTERS.map((f) => (
                <option key={f.id} value={f.id}>{f.label}</option>
              ))}
            </select>
          </div>
        </div>
      )}

      {error && <ErrorBanner message={error} onRetry={() => void reload()} />}

      {!view ? (
        !error && <Skeleton rows={6} />
      ) : isEmptyMonth(view) ? (
        <EmptyState title="Nothing in this month yet">Add tasks on the Today tab and they will show up here.</EmptyState>
      ) : (
        <>
          {view.columns.length === 0 && <p className="muted">Tasks that repeat get their own column.</p>}
          <SheetTable view={view} filter={filter} onToggle={(t, current) => void toggle(t, current)} scrollSignal={scrollSignal} />
        </>
      )}
    </div>
  );
}
