'use client';

import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import Shell from '@/components/Shell';
import { EmptyState, ErrorBanner, Skeleton } from '@/components/ui';
import { api, errorMessage } from '@/lib/web/api';
import { fmtDay, fmtMin, repeatLabel } from '@/lib/web/format';
import type { TaskDto } from '@/lib/services/tasks';

interface Page {
  query: string;
  items: TaskDto[];
  has_more: boolean;
}

const PAGE = 20;

export default function SearchPage() {
  return (
    <Shell>
      <h1>Search</h1>
      <Search />
    </Shell>
  );
}

function Search() {
  const [q, setQ] = useState('');
  const [items, setItems] = useState<TaskDto[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [searched, setSearched] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef(0);

  async function load(query: string, offset: number) {
    const mine = ++latest.current;
    setLoading(true);
    setError(null);
    try {
      const page = await api<Page>(`/search?q=${encodeURIComponent(query)}&limit=${PAGE}&offset=${offset}`);
      if (mine !== latest.current) return; // a newer search replaced this one
      setItems((prev) => (offset === 0 ? page.items : [...prev, ...page.items]));
      setHasMore(page.has_more);
      setSearched(query);
    } catch (e) {
      if (mine === latest.current) setError(errorMessage(e));
    } finally {
      if (mine === latest.current) setLoading(false);
    }
  }

  // Search as you type, after a short pause
  useEffect(() => {
    const query = q.trim();
    if (query.length < 2) {
      latest.current++;
      setItems([]);
      setSearched(null);
      setHasMore(false);
      setLoading(false);
      return;
    }
    const t = setTimeout(() => void load(query, 0), 300);
    return () => clearTimeout(t);
  }, [q]);

  return (
    <>
      <div className="card">
        <label className="sr-only" htmlFor="q">Search your tasks</label>
        <input id="q" type="search" placeholder="Search titles and notes…" autoFocus value={q} onChange={(e) => setQ(e.target.value)} />
        <p className="muted small" style={{ margin: '6px 0 0' }}>Searches every date, including finished tasks.</p>
      </div>

      {error && <ErrorBanner message={error} onRetry={() => void load(q.trim(), 0)} />}
      {loading && items.length === 0 && <Skeleton rows={3} />}

      {searched && !loading && items.length === 0 && !error && (
        <section className="card"><EmptyState title={`No tasks match “${searched}”`}>Try a different word.</EmptyState></section>
      )}

      {items.length > 0 && (
        <section className="card" aria-label="Results" aria-busy={loading}>
          {items.map((t) => (
            <div className={`task${t.status === 'done' ? ' done' : ''}`} key={t.id}>
              <div className="body">
                <div className="title">{t.title}</div>
                <div>
                  <span className="chip">{fmtDay(t.due_date)}</span>
                  <span className="chip">{t.status === 'done' ? '✓ done' : t.status === 'skipped' ? 'skipped' : 'open'}</span>
                  <span className="chip">{fmtMin(t.duration_min)}</span>
                  {t.recur !== 'none' && <span className="chip">↻ {repeatLabel(t)}</span>}
                </div>
                {t.notes && <div className="muted small" style={{ marginTop: 4, overflowWrap: 'anywhere' }}>{t.notes.length > 140 ? `${t.notes.slice(0, 140)}…` : t.notes}</div>}
              </div>
              <Link href={`/today?date=${t.due_date}`} style={{ alignSelf: 'center', whiteSpace: 'nowrap' }}>Open day</Link>
            </div>
          ))}
          {hasMore && (
            <div style={{ textAlign: 'center', marginTop: 12 }}>
              <button disabled={loading} onClick={() => void load(q.trim(), items.length)}>{loading ? 'Loading…' : 'Load more'}</button>
            </div>
          )}
        </section>
      )}
    </>
  );
}
