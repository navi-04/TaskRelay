'use client';

import { fmtDay, shiftDate, weekdayIndex, WEEKDAYS } from '@/lib/web/format';

export interface Repeat {
  mode: 'none' | 'daily' | 'days';
  /** 1=Mon..7=Sun; only used when mode is 'days'. */
  days: number[];
  /** Last day (inclusive), '' for never. */
  until: string;
}

export const NO_REPEAT: Repeat = { mode: 'none', days: [], until: '' };

/** Repeat state from a task as the API returns it. */
export function repeatFromTask(t: { recur: string; recur_days: number[] | null; recur_until: string | null }): Repeat {
  if (t.recur === 'none') return NO_REPEAT;
  return { mode: t.recur_days ? 'days' : 'daily', days: t.recur_days ?? [], until: t.recur_until ?? '' };
}

/** The API fields for a repeat. */
export function repeatToApi(r: Repeat): { recur: 'none' | 'daily'; recur_days: number[] | null; recur_until: string | null } {
  if (r.mode === 'none') return { recur: 'none', recur_days: null, recur_until: null };
  return { recur: 'daily', recur_days: r.mode === 'days' ? [...r.days].sort((a, b) => a - b) : null, recur_until: r.until || null };
}

/** The first date on or after `start` that matches the chosen weekdays (a series may start on a day that is not selected). */
export function firstMatch(start: string, days: number[]): string | null {
  for (let i = 0; i < 7; i++) {
    const d = shiftDate(start, i);
    if (days.includes(weekdayIndex(d) + 1)) return d;
  }
  return null;
}

export default function RepeatPicker({ value, onChange, start }: { value: Repeat; onChange: (r: Repeat) => void; start: string }) {
  const set = (patch: Partial<Repeat>) => onChange({ ...value, ...patch });
  const toggle = (d: number) => set({ days: value.days.includes(d) ? value.days.filter((x) => x !== d) : [...value.days, d] });
  const first = value.mode === 'days' && value.days.length > 0 ? firstMatch(start, value.days) : null;

  return (
    <fieldset style={{ border: 0, padding: 0, margin: '12px 0 0' }}>
      <legend className="muted" style={{ padding: 0, fontWeight: 500 }}>Repeat</legend>
      <div className="row wrap" role="radiogroup" aria-label="Repeat">
        {(
          [
            ['none', "Doesn't repeat"],
            ['daily', 'Every day'],
            ['days', 'Choose days'],
          ] as const
        ).map(([mode, label]) => (
          <label key={mode} className="row" style={{ margin: 0, color: 'var(--text)' }}>
            <input type="radio" name="repeat-mode" checked={value.mode === mode} onChange={() => set({ mode, days: mode === 'days' && value.days.length === 0 ? [weekdayIndex(start) + 1] : value.days })} />
            {label}
          </label>
        ))}
      </div>

      {value.mode === 'days' && (
        <>
          <div className="row wrap" style={{ marginTop: 8 }}>
            {WEEKDAYS.map((name, i) => (
              <button
                key={name}
                type="button"
                className={value.days.includes(i + 1) ? 'primary' : ''}
                aria-pressed={value.days.includes(i + 1)}
                style={{ minWidth: 48, padding: '8px 10px' }}
                onClick={() => toggle(i + 1)}
              >
                {name}
              </button>
            ))}
          </div>
          <div className="row wrap" style={{ marginTop: 4 }}>
            <button type="button" className="link" onClick={() => set({ days: [1, 2, 3, 4, 5] })}>Weekdays</button>
            <button type="button" className="link" onClick={() => set({ days: [6, 7] })}>Weekends</button>
          </div>
          {value.days.length === 0 && <p className="field-error" role="alert">Pick at least one day.</p>}
          {first && first !== start && <p className="muted">Starts {fmtDay(first)} (the first selected day on or after {fmtDay(start)}).</p>}
        </>
      )}

      {value.mode !== 'none' && (
        <>
          <label htmlFor="repeat-until">Ends on (optional)</label>
          <input id="repeat-until" type="date" min={start} value={value.until} onChange={(e) => set({ until: e.target.value })} />
        </>
      )}
    </fieldset>
  );
}
