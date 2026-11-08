'use client';

import type { HabitDto } from '@/lib/services/habits';
import type { LabelDto } from '@/lib/services/labels';
import type { TaskDto } from '@/lib/services/tasks';
import { fmtClock, fmtMin, repeatLabel } from '@/lib/web/format';
import HabitDots from './HabitDots';
import { TimeChip } from './ui';

const RECENT_MS = 48 * 3_600_000;

/** Did an AI assistant change this task (or tick it off) in the last 48 hours? An edit by the user clears it. */
export function changedByClaude(t: TaskDto, now = Date.now()): boolean {
  if (t.updated_by === 'ai' && now - Date.parse(t.updated_at) < RECENT_MS) return true;
  return t.day_updated_by === 'ai' && t.completed_at != null && now - Date.parse(t.completed_at) < RECENT_MS;
}

interface Props {
  task: TaskDto;
  priority?: LabelDto;
  habit?: HabitDto;
  busy: boolean;
  /** Whether starring is possible (the Top 3 is not full, or this task is already in it). */
  canStar: boolean;
  onToggle: (t: TaskDto) => void;
  onEdit: (t: TaskDto) => void;
  onDelete: (t: TaskDto) => void;
  onStar: (t: TaskDto) => void;
}

export default function TaskRow({ task: t, priority, habit, busy, canStar, onToggle, onEdit, onDelete, onStar }: Props) {
  const done = t.status === 'done';
  const starred = t.top_position != null;
  return (
    <div className={`task${done ? ' done' : ''}`}>
      <input
        className="check"
        type="checkbox"
        checked={done}
        disabled={busy}
        aria-label={`${done ? 'Mark not done' : 'Mark done'}: ${t.title}`}
        onChange={() => onToggle(t)}
      />
      <div className="body">
        <div className="title">{t.title}</div>
        <div>
          <TimeChip task={t} />
          <span className="chip">{fmtMin(t.duration_min)}</span>
          {t.alarm_time && <span className="chip">{t.reminder_kind === 'alarm' ? 'Alarm' : 'Reminder'} {fmtClock(t.alarm_time)}</span>}
          {t.recur !== 'none' && <span className="chip">↻ {repeatLabel(t)}</span>}
          {priority && <span className="chip">{priority.label}</span>}
          {changedByClaude(t) && <span className="chip ai">Claude</span>}
          {habit && t.recur !== 'none' && (
            <span className="chip" style={{ paddingRight: 6 }}>
              {habit.current_streak > 1 ? `${habit.current_streak}-day streak` : 'Last 7'}
              <HabitDots habit={habit} />
            </span>
          )}
        </div>
        {t.day_note && <div className="muted small" style={{ marginTop: 4 }}>“{t.day_note}”</div>}
      </div>
      <button
        className="icon star"
        aria-pressed={starred}
        aria-label={starred ? `Remove from Top 3: ${t.title}` : `Add to Top 3: ${t.title}`}
        title={starred ? 'In your Top 3' : canStar ? 'Add to Top 3' : 'Your Top 3 is full'}
        disabled={busy || (!starred && !canStar)}
        onClick={() => onStar(t)}
      >
        {starred ? '★' : '☆'}
      </button>
      <button className="icon" aria-label={`Edit: ${t.title}`} disabled={busy} onClick={() => onEdit(t)}>✎</button>
      <button className="icon" aria-label={`Delete: ${t.title}`} disabled={busy} onClick={() => onDelete(t)}>✕</button>
    </div>
  );
}
