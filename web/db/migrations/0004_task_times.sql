-- Optional time block of a task: when it starts and when it ends (the user's local time, HH:mm).
-- Additive only: existing rows get NULL for both. alarm_time (when the phone alerts) stays separate.
ALTER TABLE tasks ADD COLUMN start_time TEXT CHECK (start_time IS NULL OR start_time GLOB '[0-2][0-9]:[0-5][0-9]');
-- When both are present the end must be after the start (a block never crosses midnight).
ALTER TABLE tasks ADD COLUMN end_time TEXT CHECK (end_time IS NULL OR (end_time GLOB '[0-2][0-9]:[0-5][0-9]' AND (start_time IS NULL OR end_time > start_time)));
