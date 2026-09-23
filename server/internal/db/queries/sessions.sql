-- name: CreateSession :exec
INSERT INTO sessions (id, user_id, created_at, last_used_at)
VALUES (@id, @user_id, @now, @now);

-- name: GetActiveSession :one
SELECT * FROM sessions
WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL;

-- name: TouchSession :exec
UPDATE sessions SET last_used_at = @now WHERE id = @id;

-- name: RevokeSession :execrows
UPDATE sessions SET revoked_at = @now
WHERE id = @id AND user_id = @user_id AND revoked_at IS NULL;
