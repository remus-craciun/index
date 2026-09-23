-- name: BumpRev :one
UPDATE sync_state SET rev = rev + 1 WHERE id = 1 RETURNING rev;

-- name: CurrentRev :one
SELECT rev FROM sync_state WHERE id = 1;
