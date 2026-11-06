-- TaskRelay initial schema. Additive migrations only: never edit this file once applied.
--
-- No FOREIGN KEY clauses on purpose: Turso enforces them but a plain local libSQL file
-- (used by tests and `next dev`) does not, so they would behave differently per
-- environment. Ownership is checked in the service layer instead (every query is
-- scoped by user_id) and covered by the isolation tests.
--
-- Dates are local calendar days 'YYYY-MM-DD'. Instants are UTC ISO-8601 strings.

CREATE TABLE users (
  id                TEXT PRIMARY KEY,
  email             TEXT NOT NULL UNIQUE,
  password_hash     TEXT NOT NULL,
  timezone          TEXT NOT NULL DEFAULT 'UTC',
  ai_access_id      TEXT NOT NULL UNIQUE,
  ai_access_enabled INTEGER NOT NULL DEFAULT 1 CHECK (ai_access_enabled IN (0, 1)),
  ai_last_used_at   TEXT,
  created_at        TEXT NOT NULL
) STRICT;

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  last_used  TEXT NOT NULL
) STRICT;
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE settings (
  user_id              TEXT PRIMARY KEY,
  estimation_mode      TEXT NOT NULL DEFAULT 'time' CHECK (estimation_mode IN ('time', 'count')),
  daily_time_limit_min INTEGER NOT NULL DEFAULT 480 CHECK (daily_time_limit_min BETWEEN 15 AND 1440),
  daily_count_limit    INTEGER NOT NULL DEFAULT 10  CHECK (daily_count_limit BETWEEN 1 AND 100),
  daily_reminder_on    INTEGER NOT NULL DEFAULT 1 CHECK (daily_reminder_on IN (0, 1)),
  daily_reminder_hour  INTEGER NOT NULL DEFAULT 9  CHECK (daily_reminder_hour BETWEEN 0 AND 23),
  daily_reminder_min   INTEGER NOT NULL DEFAULT 0  CHECK (daily_reminder_min BETWEEN 0 AND 59),
  end_of_day_on        INTEGER NOT NULL DEFAULT 0 CHECK (end_of_day_on IN (0, 1)),
  end_of_day_hour      INTEGER NOT NULL DEFAULT 21 CHECK (end_of_day_hour BETWEEN 0 AND 23),
  end_of_day_min       INTEGER NOT NULL DEFAULT 0  CHECK (end_of_day_min BETWEEN 0 AND 59),
  carry_over_alerts    INTEGER NOT NULL DEFAULT 1 CHECK (carry_over_alerts IN (0, 1))
) STRICT;

-- Task types and priorities share one table (kind). color is an ARGB int like the app uses.
CREATE TABLE labels (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('type', 'priority')),
  label      TEXT NOT NULL CHECK (length(label) BETWEEN 1 AND 40),
  color      INTEGER NOT NULL DEFAULT 4284955319,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
) STRICT;
CREATE INDEX labels_user_kind ON labels (user_id, kind, sort_order);

CREATE TABLE tasks (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL,
  title         TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  notes         TEXT CHECK (notes IS NULL OR length(notes) <= 4000),
  duration_min  INTEGER NOT NULL DEFAULT 30 CHECK (duration_min BETWEEN 1 AND 1440),
  type_id       TEXT,
  priority_id   TEXT,
  due_date      TEXT NOT NULL CHECK (due_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  alarm_time    TEXT CHECK (alarm_time IS NULL OR alarm_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  reminder_kind TEXT NOT NULL DEFAULT 'alarm' CHECK (reminder_kind IN ('alarm', 'notification')),
  recur         TEXT NOT NULL DEFAULT 'none' CHECK (recur IN ('none', 'daily')),
  recur_until   TEXT CHECK (recur_until IS NULL OR recur_until GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  updated_by    TEXT NOT NULL DEFAULT 'app' CHECK (updated_by IN ('app', 'ai')),
  deleted_at    TEXT
) STRICT;
CREATE INDEX tasks_user_due ON tasks (user_id, due_date) WHERE deleted_at IS NULL;

-- One row per (task, day) that is not simply "open": completed or skipped.
-- One-off tasks use their due_date as the day. completed_on is the user's local
-- date when it was ticked, so a late completion never rewrites an earlier day.
CREATE TABLE task_days (
  task_id      TEXT NOT NULL,
  user_id      TEXT NOT NULL,
  date         TEXT NOT NULL CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  status       TEXT NOT NULL CHECK (status IN ('done', 'skipped')),
  note         TEXT CHECK (note IS NULL OR length(note) <= 1000),
  completed_at TEXT,
  completed_on TEXT,
  updated_by   TEXT NOT NULL DEFAULT 'app' CHECK (updated_by IN ('app', 'ai')),
  updated_at   TEXT NOT NULL,
  PRIMARY KEY (task_id, date)
) STRICT;
CREATE INDEX task_days_user_date ON task_days (user_id, date);

CREATE TABLE rate_limits (
  key          TEXT PRIMARY KEY,
  n            INTEGER NOT NULL,
  window_start TEXT NOT NULL
) STRICT;
