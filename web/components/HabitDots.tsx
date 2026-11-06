import type { HabitDto } from '@/lib/services/habits';
import { fmtDay } from '@/lib/web/format';

const WORD: Record<string, string> = { done: 'done', missed: 'missed', skipped: 'skipped', pending: 'to do today', none: 'not scheduled' };

/** The last 7 days of a repeating task: filled = done, red ring = missed, dashed = skipped, small = not scheduled. */
export default function HabitDots({ habit }: { habit: HabitDto }) {
  const summary = habit.last7.map((d) => `${fmtDay(d.date)} ${WORD[d.state]}`).join(', ');
  return (
    <span className="dots" role="img" aria-label={`Last 7 days: ${summary}`} title={habit.current_streak > 1 ? `${habit.current_streak} in a row` : undefined}>
      {habit.last7.map((d) => (
        <span key={d.date} className={`dot ${d.state}`} />
      ))}
    </span>
  );
}
