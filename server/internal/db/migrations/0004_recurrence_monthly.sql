-- +goose NO TRANSACTION
-- SQLite can't alter a CHECK constraint, so the table is rebuilt to allow
-- frequency = 'monthly' and add month_day. Foreign keys are switched off
-- for the rebuild: otherwise dropping the old table would cascade-delete
-- every task that references a recurrence. (The pragma is ignored inside a
-- transaction, hence NO TRANSACTION.)

-- +goose Up
PRAGMA foreign_keys = OFF;

CREATE TABLE recurrences_new (
    id                TEXT PRIMARY KEY,
    user_id           TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title             TEXT NOT NULL,
    notes             TEXT NOT NULL DEFAULT '',
    -- 'daily':   every repeat_interval days from start_date.
    -- 'weekly':  on the weekdays mask, every repeat_interval weeks counted
    --            from the Monday-based week containing start_date.
    -- 'monthly': on month_day (clamped to the month's last day), every
    --            repeat_interval months counted from start_date's month.
    frequency         TEXT NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('daily', 'weekly', 'monthly')),
    repeat_interval   INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval BETWEEN 1 AND 365),
    weekdays          INTEGER NOT NULL CHECK (weekdays BETWEEN 1 AND 127),
    month_day         INTEGER CHECK (month_day BETWEEN 1 AND 31),
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

INSERT INTO recurrences_new (id, user_id, title, notes, frequency, repeat_interval, weekdays, start_time, end_time,
                             estimated_minutes, reminder_minutes, start_date, end_date, status,
                             created_at, updated_at, deleted_at, server_rev)
SELECT id, user_id, title, notes, frequency, repeat_interval, weekdays, start_time, end_time,
       estimated_minutes, reminder_minutes, start_date, end_date, status,
       created_at, updated_at, deleted_at, server_rev
FROM recurrences;

DROP TABLE recurrences;
ALTER TABLE recurrences_new RENAME TO recurrences;
CREATE INDEX recurrences_user_rev ON recurrences (user_id, server_rev);

PRAGMA foreign_keys = ON;

-- +goose Down
PRAGMA foreign_keys = OFF;

CREATE TABLE recurrences_old (
    id                TEXT PRIMARY KEY,
    user_id           TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title             TEXT NOT NULL,
    notes             TEXT NOT NULL DEFAULT '',
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
    server_rev        INTEGER NOT NULL,
    frequency         TEXT NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('daily', 'weekly')),
    repeat_interval   INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval BETWEEN 1 AND 365)
);
INSERT INTO recurrences_old (id, user_id, title, notes, weekdays, start_time, end_time, estimated_minutes,
                             reminder_minutes, start_date, end_date, status, created_at, updated_at, deleted_at,
                             server_rev, frequency, repeat_interval)
SELECT id, user_id, title, notes, weekdays, start_time, end_time, estimated_minutes,
       reminder_minutes, start_date, end_date, status, created_at, updated_at, deleted_at,
       server_rev, CASE frequency WHEN 'monthly' THEN 'weekly' ELSE frequency END, repeat_interval
FROM recurrences;
DROP TABLE recurrences;
ALTER TABLE recurrences_old RENAME TO recurrences;
CREATE INDEX recurrences_user_rev ON recurrences (user_id, server_rev);

PRAGMA foreign_keys = ON;
