import { WEEKDAYS, weekdayIndex } from '@/lib/web/format';

export interface BarDatum {
  date: string;
  planned: number;
  done: number;
}

/** Planned (grey) vs done (teal) per day. Values are printed, so colour is never the only cue. */
export function BarChart({ days }: { days: BarDatum[] }) {
  const max = Math.max(1, ...days.map((d) => d.planned));
  return (
    <div className="bars" role="img" aria-label={`Done out of planned: ${days.map((d) => `${WEEKDAYS[weekdayIndex(d.date)]} ${d.done} of ${d.planned}`).join(', ')}`}>
      {days.map((d) => (
        <div className="col" key={d.date} aria-hidden="true">
          <span>{d.planned === 0 ? '–' : `${d.done}/${d.planned}`}</span>
          <div style={{ position: 'relative', width: '100%', maxWidth: 36, height: `${(d.planned / max) * 80}%`, minHeight: 3 }}>
            <div className="b bg" style={{ position: 'absolute', inset: 0 }} />
            <div className="b" style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: d.planned === 0 ? 0 : `${(d.done / d.planned) * 100}%`, maxWidth: 'none' }} />
          </div>
          <span>{WEEKDAYS[weekdayIndex(d.date)]}</span>
        </div>
      ))}
    </div>
  );
}
