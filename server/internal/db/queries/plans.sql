-- name: ListPlans :many
SELECT * FROM learning_plans
WHERE user_id = @user_id AND deleted_at IS NULL
ORDER BY created_at;

-- name: GetPlan :one
SELECT * FROM learning_plans
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: GetPlanIncludingDeleted :one
SELECT * FROM learning_plans
WHERE id = @id AND user_id = @user_id;

-- name: InsertPlan :exec
INSERT INTO learning_plans (id, user_id, title, description, target_date, status, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @user_id, @title, @description, @target_date, @status, @created_at, @updated_at, NULL, @server_rev);

-- name: UpdatePlan :exec
UPDATE learning_plans
SET title = @title, description = @description, target_date = @target_date, status = @status,
    updated_at = @updated_at, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id;

-- name: SoftDeletePlan :execrows
UPDATE learning_plans
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: UpsertPlanLWW :execrows
INSERT INTO learning_plans (id, user_id, title, description, target_date, status, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @user_id, @title, @description, @target_date, @status, @created_at, @updated_at, @deleted_at, @server_rev)
ON CONFLICT (id) DO UPDATE SET
    title = excluded.title,
    description = excluded.description,
    target_date = excluded.target_date,
    status = excluded.status,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at,
    server_rev = excluded.server_rev
WHERE excluded.updated_at > learning_plans.updated_at
  AND learning_plans.user_id = excluded.user_id;

-- name: ListPlansChangedSince :many
SELECT * FROM learning_plans
WHERE user_id = @user_id AND server_rev > @cursor
ORDER BY server_rev;
