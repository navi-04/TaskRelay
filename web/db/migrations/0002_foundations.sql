-- Foundations for weekday repeats, the phone feed and cheaper history scans. Additive only.

-- Repeat on chosen weekdays: Mon=bit0 .. Sun=bit6; NULL = every day. `recur` stays 'none' | 'daily'
-- ('daily' now means "repeating"), because SQLite cannot alter an existing CHECK constraint.
ALTER TABLE tasks ADD COLUMN recur_days INTEGER CHECK (recur_days IS NULL OR recur_days BETWEEN 1 AND 127);

-- Bumped by every write to phone-visible data (tasks, task_days, labels, settings, top-3, timezone).
-- /sync derives its ETag from it so an unchanged phone costs ~2 row reads.
ALTER TABLE users ADD COLUMN data_version INTEGER NOT NULL DEFAULT 0;

CREATE INDEX tasks_recurring ON tasks (user_id, due_date) WHERE deleted_at IS NULL AND recur = 'daily';
CREATE INDEX tasks_deleted ON tasks (user_id, deleted_at) WHERE deleted_at IS NOT NULL;
