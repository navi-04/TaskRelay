-- Today's Top 3 and the AI activity log. Additive only.

-- Up to three starred "must do" tasks per user per day. Rows are kept when a task is deleted/skipped/moved
-- (reads join live tasks, so the slot frees up), which lets "restore" bring a starred task back.
CREATE TABLE day_focus (
  user_id  TEXT NOT NULL,
  date     TEXT NOT NULL CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  task_id  TEXT NOT NULL,
  position INTEGER NOT NULL CHECK (position BETWEEN 1 AND 3),
  PRIMARY KEY (user_id, date, position),
  UNIQUE (user_id, date, task_id)
) STRICT;

-- What an AI assistant changed (only AI writes are logged; the user sees their own edits happen).
-- kind/actor are plain TEXT on purpose: a CHECK cannot be altered later, so TypeScript validates them.
CREATE TABLE activity (
  id      INTEGER PRIMARY KEY,
  user_id TEXT NOT NULL,
  at      TEXT NOT NULL,
  actor   TEXT NOT NULL,
  kind    TEXT NOT NULL,
  task_id TEXT NOT NULL,
  title   TEXT NOT NULL,
  date    TEXT,
  detail  TEXT
) STRICT;
CREATE INDEX activity_user ON activity (user_id, id DESC);
