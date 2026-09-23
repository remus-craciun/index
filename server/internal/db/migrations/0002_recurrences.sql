-- +goose Up

-- Repeating task rules. Clients materialise one task per matching day with a
-- deterministic ID derived from (recurrence id, date), so occurrences
-- generated on different devices are the same row.
CREATE TABLE recurrences (
    id                TEXT PRIMARY KEY,
    user_id           TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title             TEXT NOT NULL,
    notes             TEXT NOT NULL DEFAULT '',
    -- Bitmask of ISO weekdays: Monday = 1, Tuesday = 2, ... Sunday = 64.
    weekdays          INTEGER NOT NULL CHECK (weekdays BETWEEN 1 AND 127),
    start_time        TEXT,
    end_time          TEXT,
    estimated_minutes INTEGER,
    reminder_minutes  INTEGER,
    start_date        TEXT NOT NULL,
    end_date          TEXT,
    status            TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused')),
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL,
    deleted_at        TEXT,
    server_rev        INTEGER NOT NULL
);
CREATE INDEX recurrences_user_rev ON recurrences (user_id, server_rev);

ALTER TABLE tasks ADD COLUMN recurrence_id TEXT REFERENCES recurrences (id) ON DELETE CASCADE;
-- Optional time window on the scheduled day, HH:MM (24h, local time).
ALTER TABLE tasks ADD COLUMN start_time TEXT;
ALTER TABLE tasks ADD COLUMN end_time TEXT;
-- Remind this many minutes before the start (09:00 when there is no start time).
ALTER TABLE tasks ADD COLUMN reminder_minutes INTEGER;
-- When the task was completed or skipped; NULL while pending.
ALTER TABLE tasks ADD COLUMN completed_at TEXT;
CREATE INDEX tasks_recurrence ON tasks (recurrence_id);

-- +goose Down
DROP INDEX tasks_recurrence;
ALTER TABLE tasks DROP COLUMN completed_at;
ALTER TABLE tasks DROP COLUMN reminder_minutes;
ALTER TABLE tasks DROP COLUMN end_time;
ALTER TABLE tasks DROP COLUMN start_time;
ALTER TABLE tasks DROP COLUMN recurrence_id;
DROP TABLE recurrences;
