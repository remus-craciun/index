-- +goose Up

-- Timestamps are TEXT in the fixed-width UTC form 2006-01-02T15:04:05.000Z
-- (see internal/timeutil) so string comparison matches chronological order.
-- Dates are TEXT in the form YYYY-MM-DD.

CREATE TABLE users (
    id              TEXT PRIMARY KEY,
    email           TEXT NOT NULL UNIQUE COLLATE NOCASE,
    hashed_password TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

-- Single-row counter. Every write transaction bumps it once and stamps the
-- rows it touches with the new value (server_rev). Sync clients pull rows
-- with server_rev greater than their cursor.
CREATE TABLE sync_state (
    id  INTEGER PRIMARY KEY CHECK (id = 1),
    rev INTEGER NOT NULL
);
INSERT INTO sync_state (id, rev) VALUES (1, 0);

CREATE TABLE learning_plans (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    target_date TEXT,
    status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    deleted_at  TEXT,
    server_rev  INTEGER NOT NULL
);
CREATE INDEX learning_plans_user_rev ON learning_plans (user_id, server_rev);

CREATE TABLE milestones (
    id          TEXT PRIMARY KEY,
    plan_id     TEXT NOT NULL REFERENCES learning_plans (id) ON DELETE CASCADE,
    user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    order_index INTEGER NOT NULL DEFAULT 0,
    status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    deleted_at  TEXT,
    server_rev  INTEGER NOT NULL
);
CREATE INDEX milestones_plan ON milestones (plan_id);
CREATE INDEX milestones_user_rev ON milestones (user_id, server_rev);

CREATE TABLE tasks (
    id                TEXT PRIMARY KEY,
    user_id           TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    milestone_id      TEXT REFERENCES milestones (id) ON DELETE CASCADE,
    title             TEXT NOT NULL,
    notes             TEXT NOT NULL DEFAULT '',
    scheduled_date    TEXT,
    estimated_minutes INTEGER,
    status            TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'skipped')),
    created_at        TEXT NOT NULL,
    updated_at        TEXT NOT NULL,
    deleted_at        TEXT,
    server_rev        INTEGER NOT NULL
);
CREATE INDEX tasks_user_date ON tasks (user_id, scheduled_date);
CREATE INDEX tasks_milestone ON tasks (milestone_id);
CREATE INDEX tasks_user_rev ON tasks (user_id, server_rev);

-- +goose Down
DROP TABLE tasks;
DROP TABLE milestones;
DROP TABLE learning_plans;
DROP TABLE sync_state;
DROP TABLE users;
