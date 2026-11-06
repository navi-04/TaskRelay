'use client';

import { useEffect, useRef, useState, type FormEvent } from 'react';
import { api, errorMessage } from '@/lib/web/api';
import { fmtDay, pad2 } from '@/lib/web/format';
import type { LabelDto } from '@/lib/services/labels';
import type { TaskDto } from '@/lib/services/tasks';
import RepeatPicker, { repeatFromTask, repeatToApi, NO_REPEAT, type Repeat } from './RepeatPicker';

const DURATIONS = [15, 30, 45, 60, 90, 120];

interface Props {
  /** The task being edited; omit to create. */
  task?: TaskDto;
  /** The day the task is created for (or the day being viewed while editing). */
  date: string;
  /** The server's idea of today, for the "won't ring today" warning. */
  today: string;
  types: LabelDto[];
  priorities: LabelDto[];
  onClose: () => void;
  onSaved: (task: TaskDto) => void;
}

/** One form for creating and editing a task. A native modal <dialog>: focus is trapped and Esc closes it. */
export default function TaskForm({ task, date, today, types, priorities, onClose, onSaved }: Props) {
  const dialog = useRef<HTMLDialogElement>(null);
  // Generated once per open, so a retried (timed-out) create can't make a duplicate.
  const newId = useRef(crypto.randomUUID());

  const [title, setTitle] = useState(task?.title ?? '');
  const [notes, setNotes] = useState(task?.notes ?? '');
  const [minutes, setMinutes] = useState(String(task?.duration_min ?? 30));
  const [priorityId, setPriorityId] = useState(task?.priority_id ?? '');
  const [typeId, setTypeId] = useState(task?.type_id ?? '');
  const [dueDate, setDueDate] = useState(task?.due_date ?? date);
  const [alarm, setAlarm] = useState(task?.alarm_time ?? '');
  const [kind, setKind] = useState<'alarm' | 'notification'>(task?.reminder_kind ?? 'alarm');
  const [repeat, setRepeat] = useState<Repeat>(task ? repeatFromTask(task) : NO_REPEAT);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    dialog.current?.showModal();
  }, []);

  const mins = Number(minutes);
  const minutesOk = Number.isInteger(mins) && mins >= 1 && mins <= 1440;
  const titleOk = title.trim().length >= 1 && title.length <= 200;
  const daysOk = repeat.mode !== 'days' || repeat.days.length > 0;
  const untilOk = !repeat.until || repeat.until >= dueDate;
  const valid = titleOk && minutesOk && daysOk && untilOk && notes.length <= 4000;

  const now = new Date();
  const nowHm = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const rings = alarm !== '' && dueDate === today && repeat.mode === 'none' && alarm <= nowHm;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid || busy) return;
    setBusy(true);
    setError(null);
    const fields = {
      title: title.trim(),
      notes: notes.trim() === '' ? null : notes,
      duration_min: mins,
      type_id: typeId || null,
      priority_id: priorityId || null,
      due_date: dueDate,
      alarm_time: alarm || null,
      reminder_kind: kind,
      ...repeatToApi(repeat),
    };
    try {
      const saved = task
        ? await api<TaskDto>(`/tasks/${task.id}`, { method: 'PATCH', body: fields })
        : await api<TaskDto>('/tasks', { method: 'POST', body: { id: newId.current, ...fields } });
      onSaved(saved);
    } catch (err) {
      setError(errorMessage(err)); // stay open: nothing is lost and nothing pretends to have worked
      setBusy(false);
    }
  }

  return (
    <dialog ref={dialog} aria-labelledby="task-form-title" onClose={onClose} onCancel={(e) => busy && e.preventDefault()}>
      <form onSubmit={submit} noValidate>
        <h2 id="task-form-title">{task ? 'Edit task' : `New task · ${fmtDay(dueDate)}`}</h2>
        {error && <div className="banner" role="alert">{error}</div>}
        {task && task.recur !== 'none' && <p className="muted">This is a repeating task: changes apply to every day of the series.</p>}

        <label htmlFor="tf-title">Title</label>
        <input id="tf-title" value={title} maxLength={200} autoFocus required aria-invalid={!titleOk && title !== ''} onChange={(e) => setTitle(e.target.value)} />

        <label htmlFor="tf-date">{repeat.mode === 'none' ? 'Day' : 'Starts'}</label>
        <input id="tf-date" type="date" value={dueDate} required onChange={(e) => setDueDate(e.target.value)} />

        <label htmlFor="tf-min">Time needed (minutes)</label>
        <div className="row wrap" role="group" aria-label="Quick durations">
          {DURATIONS.map((d) => (
            <button key={d} type="button" className={mins === d ? 'primary' : ''} aria-pressed={mins === d} style={{ padding: '6px 12px', minHeight: 40 }} onClick={() => setMinutes(String(d))}>
              {d}
            </button>
          ))}
        </div>
        <input id="tf-min" type="number" inputMode="numeric" min={1} max={1440} value={minutes} style={{ marginTop: 8 }} aria-invalid={!minutesOk} onChange={(e) => setMinutes(e.target.value)} />
        {!minutesOk && <p className="field-error" role="alert">Enter a whole number from 1 to 1440.</p>}

        <div className="row" style={{ alignItems: 'flex-start' }}>
          <div className="grow">
            <label htmlFor="tf-pri">Priority</label>
            <select id="tf-pri" value={priorityId} onChange={(e) => setPriorityId(e.target.value)}>
              <option value="">None</option>
              {priorities.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
            </select>
          </div>
          <div className="grow">
            <label htmlFor="tf-type">Type</label>
            <select id="tf-type" value={typeId} onChange={(e) => setTypeId(e.target.value)}>
              <option value="">None</option>
              {types.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
            </select>
          </div>
        </div>

        <label htmlFor="tf-alarm">Reminder time (optional)</label>
        <div className="row">
          <input id="tf-alarm" type="time" value={alarm} onChange={(e) => setAlarm(e.target.value)} />
          {alarm && <button type="button" className="link" onClick={() => setAlarm('')}>Clear</button>}
        </div>
        {alarm && (
          <div className="row" role="radiogroup" aria-label="Reminder type" style={{ marginTop: 8 }}>
            <label className="row" style={{ margin: 0, color: 'var(--text)' }}><input type="radio" name="kind" checked={kind === 'alarm'} onChange={() => setKind('alarm')} /> Alarm</label>
            <label className="row" style={{ margin: 0, color: 'var(--text)' }}><input type="radio" name="kind" checked={kind === 'notification'} onChange={() => setKind('notification')} /> Notification</label>
          </div>
        )}
        {rings && <p className="field-error">That time has already passed today, so it won’t ring today.</p>}

        <RepeatPicker value={repeat} onChange={setRepeat} start={dueDate} />
        {!untilOk && <p className="field-error" role="alert">The end date can’t be before the start.</p>}

        <label htmlFor="tf-notes">Notes (optional)</label>
        <textarea id="tf-notes" value={notes} maxLength={4000} onChange={(e) => setNotes(e.target.value)} />

        <div className="row" style={{ marginTop: 20, justifyContent: 'flex-end' }}>
          <button type="button" onClick={() => dialog.current?.close()} disabled={busy}>Cancel</button>
          <button className="primary" disabled={!valid || busy}>{busy ? 'Saving…' : task ? 'Save' : 'Add task'}</button>
        </div>
      </form>
    </dialog>
  );
}
