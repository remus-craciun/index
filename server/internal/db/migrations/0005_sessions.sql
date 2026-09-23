-- +goose Up

-- One row per login. Refresh tokens carry the session id and don't expire;
-- logging out revokes the session, which invalidates its refresh token.
CREATE TABLE sessions (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at   TEXT NOT NULL,
    last_used_at TEXT NOT NULL,
    revoked_at   TEXT
);
CREATE INDEX sessions_user ON sessions (user_id);

-- +goose Down
DROP TABLE sessions;
