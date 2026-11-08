import { describe, expect, it } from 'vitest';
import type { TaskDto } from '../lib/services/tasks';
import { taskCreate, taskPatch } from '../lib/validation';
import { blockMinutes, changedFields, END_BEFORE_START, taskFields, timesError, type TaskFormState } from '../lib/web/taskform';

// The task form's rules, as pure functions: the start/end pair, and what a new task or an edit sends.

const form = (over: Partial<TaskFormState> = {}): TaskFormState => ({
  title: 'Deep work',
  notes: '',
  minutes: 30,
  typeId: '',
  priorityId: '',
  dueDate: '2026-11-06',
  alarm: '',
  startTime: '',
  endTime: '',
  kind: 'alarm',
  repeat: { recur: 'none', recur_days: null, recur_until: null },
  ...over,
});

const saved = (over: Partial<TaskDto> = {}): TaskDto => ({
  id: 'tf-task-0001',
  title: 'Deep work',
  notes: null,
  duration_min: 30,
  type_id: null,
  priority_id: null,
  due_date: '2026-11-06',
  alarm_time: null,
  start_time: null,
  end_time: null,
  reminder_kind: 'alarm',
  recur: 'none',
  recur_until: null,
  recur_days: null,
  created_at: '2026-11-06T08:00:00.000Z',
  updated_at: '2026-11-06T08:00:00.000Z',
  updated_by: 'app',
  date: '2026-11-06',
  status: 'open',
  day_note: null,
  completed_at: null,
  day_updated_by: null,
  top_position: null,
  ...over,
});

describe('the start/end pair', () => {
  it('only an end that is not after the start is a problem, and either side may be empty', () => {
    expect(timesError('', '')).toBeNull();
    expect(timesError('09:00', '')).toBeNull();
    expect(timesError('', '17:00')).toBeNull();
    expect(timesError('09:00', '10:30')).toBeNull();
    expect(timesError('00:00', '23:59')).toBeNull();
    expect(timesError('10:00', '10:00')).toBe(END_BEFORE_START); // no length is not a block
    expect(timesError('10:00', '09:59')).toBe(END_BEFORE_START);
    expect(timesError('23:00', '01:00')).toBe(END_BEFORE_START); // a block never runs overnight
  });

  it('says the same words as the server', () => {
    const parsed = taskCreate.safeParse({ title: 'X', due_date: '2026-11-06', start_time: '10:00', end_time: '09:00' });
    expect(parsed.success).toBe(false);
    expect(parsed.error?.issues[0].path).toEqual(['end_time']);
    expect(parsed.error?.issues[0].message).toBe(timesError('10:00', '09:00'));
  });

  it('gives the length of a block only when both times are set and in order', () => {
    expect(blockMinutes('09:00', '10:30')).toBe(90);
    expect(blockMinutes('09:00', '09:01')).toBe(1);
    expect(blockMinutes('00:00', '23:59')).toBe(1439);
    expect(blockMinutes('09:00', '')).toBeNull();
    expect(blockMinutes('', '10:30')).toBeNull();
    expect(blockMinutes('', '')).toBeNull();
    expect(blockMinutes('10:00', '10:00')).toBeNull();
    expect(blockMinutes('10:30', '09:00')).toBeNull();
  });
});

describe('what a new task sends', () => {
  it('sends the estimate when the times do not both exist, with null for a time that is not set', () => {
    expect(taskFields(form({ minutes: 45 }))).toMatchObject({ duration_min: 45, start_time: null, end_time: null });
    expect(taskFields(form({ minutes: 45, startTime: '09:00' }))).toMatchObject({ duration_min: 45, start_time: '09:00', end_time: null }); // the block lasts the estimate
    expect(taskFields(form({ minutes: 45, endTime: '17:00' }))).toMatchObject({ duration_min: 45, start_time: null, end_time: '17:00' }); // a deadline
  });

  it('never sends a duration with both times: the server works it out', () => {
    const fields = taskFields(form({ minutes: 15, startTime: '09:00', endTime: '10:30' }));
    expect(fields).toMatchObject({ start_time: '09:00', end_time: '10:30' });
    expect('duration_min' in fields).toBe(false);
    for (const start of ['', '09:00']) {
      for (const end of ['', '10:30']) {
        expect('duration_min' in taskFields(form({ startTime: start, endTime: end }))).toBe(!(start && end));
      }
    }
  });

  it('tidies the other fields the way the form always has', () => {
    const fields = taskFields(form({ title: '  Call Bob  ', notes: '   ', typeId: 'type-1234', alarm: '08:45', kind: 'notification', repeat: { recur: 'daily', recur_days: [1, 3, 5], recur_until: '2026-12-31' } }));
    expect(fields).toMatchObject({
      title: 'Call Bob',
      notes: null,
      type_id: 'type-1234',
      priority_id: null,
      alarm_time: '08:45',
      reminder_kind: 'notification',
      recur: 'daily',
      recur_days: [1, 3, 5],
      recur_until: '2026-12-31',
    });
    expect(taskFields(form({ notes: ' keep my spaces ' })).notes).toBe(' keep my spaces ');
  });

  it('is always accepted by the server\'s own validation', () => {
    for (const [startTime, endTime] of [['', ''], ['09:00', ''], ['', '17:00'], ['09:00', '10:30']]) {
      const body = { id: 'tf-new-00001', ...taskFields(form({ startTime, endTime, alarm: '08:30' })) };
      expect(taskCreate.safeParse(body).success, JSON.stringify(body)).toBe(true);
    }
  });
});

describe('what an edit sends', () => {
  it('sends nothing when nothing changed, even for a task that has both times', () => {
    expect(changedFields(taskFields(form()), saved())).toEqual({});
    const timed = saved({ start_time: '09:00', end_time: '10:30', duration_min: 90 });
    expect(changedFields(taskFields(form({ minutes: 90, startTime: '09:00', endTime: '10:30' })), timed)).toEqual({});
    const repeating = saved({ recur: 'daily', recur_days: [1, 3, 5], recur_until: '2026-12-31', alarm_time: '08:45', notes: 'Bring water' });
    const same = form({ notes: 'Bring water', alarm: '08:45', repeat: { recur: 'daily', recur_days: [1, 3, 5], recur_until: '2026-12-31' } });
    expect(changedFields(taskFields(same), repeating)).toEqual({});
  });

  it('sends only the field that changed', () => {
    expect(changedFields(taskFields(form({ title: 'Deep work 2' })), saved())).toEqual({ title: 'Deep work 2' });
    expect(changedFields(taskFields(form({ priorityId: 'pri-12345' })), saved())).toEqual({ priority_id: 'pri-12345' });
    expect(changedFields(taskFields(form({ repeat: { recur: 'daily', recur_days: [2, 4], recur_until: null } })), saved())).toEqual({ recur: 'daily', recur_days: [2, 4] });
    const repeating = saved({ recur: 'daily', recur_days: [1, 3, 5] });
    expect(changedFields(taskFields(form({ repeat: { recur: 'daily', recur_days: [1, 3, 6], recur_until: null } })), repeating)).toEqual({ recur_days: [1, 3, 6] });
  });

  it('adding a time sends just that time, and the estimate only if it was changed too', () => {
    expect(changedFields(taskFields(form({ startTime: '09:00' })), saved())).toEqual({ start_time: '09:00' });
    expect(changedFields(taskFields(form({ startTime: '09:00', minutes: 50 })), saved())).toEqual({ start_time: '09:00', duration_min: 50 });
    expect(changedFields(taskFields(form({ endTime: '17:00' })), saved())).toEqual({ end_time: '17:00' });
  });

  it('setting both times sends both and no duration, whatever the form held as the estimate', () => {
    expect(changedFields(taskFields(form({ startTime: '09:00', endTime: '10:30', minutes: 15 })), saved())).toEqual({ start_time: '09:00', end_time: '10:30' });
  });

  it('moving one side of a block sends only that side; the server recomputes the length', () => {
    const timed = saved({ start_time: '09:00', end_time: '10:30', duration_min: 90 });
    expect(changedFields(taskFields(form({ startTime: '09:00', endTime: '12:00', minutes: 180 })), timed)).toEqual({ end_time: '12:00' });
    expect(changedFields(taskFields(form({ startTime: '09:30', endTime: '10:30', minutes: 60 })), timed)).toEqual({ start_time: '09:30' });
  });

  it('removing a time sends null, and the estimate is only sent if it differs from the saved one', () => {
    const timed = saved({ start_time: '09:00', end_time: '10:30', duration_min: 90 });
    // the form keeps the last length as the estimate (90), so it matches what the server keeps
    expect(changedFields(taskFields(form({ startTime: '09:00', endTime: '', minutes: 90 })), timed)).toEqual({ end_time: null });
    expect(changedFields(taskFields(form({ startTime: '', endTime: '10:30', minutes: 90 })), timed)).toEqual({ start_time: null });
    expect(changedFields(taskFields(form({ startTime: '', endTime: '', minutes: 90 })), timed)).toEqual({ start_time: null, end_time: null });
    // and a new estimate chosen after removing the end goes along with it
    expect(changedFields(taskFields(form({ startTime: '09:00', endTime: '', minutes: 45 })), timed)).toEqual({ end_time: null, duration_min: 45 });
    // a start alone: removing it clears the field too
    expect(changedFields(taskFields(form({ minutes: 30 })), saved({ start_time: '09:00' }))).toEqual({ start_time: null });
  });

  it('is always accepted by the server\'s own validation', () => {
    const timed = saved({ start_time: '09:00', end_time: '10:30', duration_min: 90 });
    const cases: Array<[TaskFormState, TaskDto]> = [
      [form({ title: 'Renamed' }), saved()],
      [form({ startTime: '09:00' }), saved()],
      [form({ startTime: '09:00', endTime: '10:30', minutes: 15 }), saved()],
      [form({ startTime: '09:00', endTime: '12:00', minutes: 180 }), timed],
      [form({ startTime: '09:00', endTime: '', minutes: 90 }), timed],
      [form({ startTime: '', endTime: '', minutes: 90 }), timed],
    ];
    for (const [state, task] of cases) {
      const patch = changedFields(taskFields(state), task);
      expect(taskPatch.safeParse(patch).success, JSON.stringify(patch)).toBe(true);
    }
  });
});
