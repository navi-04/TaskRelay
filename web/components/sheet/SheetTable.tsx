'use client';

import { useEffect, useRef } from 'react';
import { fmtMin, fmtMonth, WEEKDAYS } from '@/lib/web/format';
import { cellLabel, filterDays, habitMeta, isFullDay, isMissedDay, isTogglable, pctText, shortDate, type SheetFilter } from '@/lib/web/sheet';
import type { CellState, SheetView } from '@/lib/services/sheet';

export interface ToggleTarget {
  id: string;
  title: string;
  date: string;
  weekday: number;
}

/** Symbols, so state is never carried by colour alone. */
const BOX: Record<CellState, string> = { done: '✓', skipped: '–', open: '' };
const PILL: Record<CellState, string> = { done: '✓', skipped: '–', open: '○' };

interface Props {
  view: SheetView;
  filter: SheetFilter;
  onToggle: (target: ToggleTarget, current: CellState) => void;
  /** Bumped by the "Today" button: scroll today's row into view (smoothly). */
  scrollSignal: number;
}

/** The spreadsheet: one row per day, one tick column per repeating task, that day's one-off tasks, and totals. */
export default function SheetTable({ view, filter, onToggle, scrollSignal }: Props) {
  const regionRef = useRef<HTMLDivElement>(null);
  const todayRef = useRef<HTMLTableRowElement>(null);
  const lastSignal = useRef(scrollSignal);

  // Bring today's row to the middle of the visible rows: when a month opens, and whenever "Today" is pressed.
  useEffect(() => {
    const smooth = lastSignal.current !== scrollSignal;
    lastSignal.current = scrollSignal;
    const region = regionRef.current;
    const row = todayRef.current;
    if (!region || !row) return;
    const head = region.querySelector('thead')?.getBoundingClientRect().height ?? 0;
    const rowTop = row.getBoundingClientRect().top - region.getBoundingClientRect().top + region.scrollTop;
    const top = rowTop + row.offsetHeight / 2 - head - (region.clientHeight - head) / 2;
    const reduce = typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    region.scrollTo({ top: Math.max(0, top), behavior: smooth && !reduce ? 'smooth' : 'auto' });
  }, [view.from, scrollSignal]);

  const days = filterDays(view.days, filter);
  const columnCount = 7 + view.columns.length;

  return (
    <div className="sheet-region" role="region" aria-label="Task sheet" tabIndex={0} ref={regionRef}>
      <table className="sheet">
        <caption className="sr-only">Tasks for {fmtMonth(view.from)}, one row per day</caption>
        <thead>
          <tr>
            <th scope="col" className="sticky c-date">Date</th>
            <th scope="col" className="sticky c-day">Day</th>
            {view.columns.map((c) => (
              <th scope="col" key={c.task_id} className="c-habit" title={c.title}>
                <span className="h-title">{c.title}</span>
                <span className="h-meta">{habitMeta(c)}</span>
              </th>
            ))}
            <th scope="col" className="c-tasks">Tasks</th>
            <th scope="col" className="c-num">Done</th>
            <th scope="col" className="c-num">Total</th>
            <th scope="col" className="c-num">%</th>
            <th scope="col" className="c-notes">Notes</th>
          </tr>
        </thead>
        <tbody>
          {days.length === 0 && (
            <tr>
              <td colSpan={columnCount} className="sheet-none">No days match this filter.</td>
            </tr>
          )}
          {days.map((d) => (
            <tr
              key={d.date}
              ref={d.is_today ? todayRef : undefined}
              className={[d.is_weekend ? 'weekend' : '', d.is_today ? 'today' : ''].filter(Boolean).join(' ')}
            >
              <th scope="row" className="sticky c-date" aria-current={d.is_today ? 'date' : undefined}>{shortDate(d.date)}</th>
              <td className="sticky c-day">{WEEKDAYS[d.weekday - 1]}</td>

              {view.columns.map((c) => {
                const state = d.cells[c.task_id];
                if (!isTogglable(state)) {
                  return (
                    <td key={c.task_id} className="c-habit na">
                      <span className="sr-only">Not scheduled</span>
                    </td>
                  );
                }
                return (
                  <td key={c.task_id} className="c-habit">
                    <button
                      type="button"
                      className="cell"
                      aria-pressed={state === 'done'}
                      aria-label={cellLabel(c.title, d, state)}
                      onClick={() => onToggle({ id: c.task_id, title: c.title, date: d.date, weekday: d.weekday }, state)}
                    >
                      <span className={`box ${state}`} aria-hidden="true">{BOX[state]}</span>
                    </button>
                  </td>
                );
              })}

              <td className="c-tasks">
                {d.tasks.length > 0 && (
                  <div className="sheet-tasks">
                    {d.tasks.map((t) => (
                      <button
                        type="button"
                        key={t.id}
                        className="pill"
                        aria-pressed={t.status === 'done'}
                        aria-label={cellLabel(t.title, d, t.status)}
                        onClick={() => onToggle({ id: t.id, title: t.title, date: d.date, weekday: d.weekday }, t.status)}
                      >
                        <span aria-hidden="true">{PILL[t.status]}</span>
                        <span className="t-title">{t.title}</span>
                        <span className="t-min">{fmtMin(t.duration_min)}</span>
                      </button>
                    ))}
                  </div>
                )}
              </td>

              <td className="c-num">{d.done}</td>
              <td className="c-num">{d.planned}</td>
              <td className={['c-num', 'pct', isFullDay(d) ? 'full' : '', isMissedDay(d, view.today) ? 'missed' : ''].filter(Boolean).join(' ')}>
                {pctText(d)}
              </td>
              <td className="c-notes">
                {d.notes.map((n, i) => (
                  <div key={i}>{n}</div>
                ))}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
