-- name: ListMilestonesByPlan :many
SELECT * FROM milestones
WHERE plan_id = @plan_id AND user_id = @user_id AND deleted_at IS NULL
ORDER BY order_index, created_at;

-- name: GetMilestone :one
SELECT * FROM milestones
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: GetMilestoneIncludingDeleted :one
SELECT * FROM milestones
WHERE id = @id AND user_id = @user_id;

-- name: InsertMilestone :exec
INSERT INTO milestones (id, plan_id, user_id, title, order_index, status, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @plan_id, @user_id, @title, @order_index, @status, @created_at, @updated_at, NULL, @server_rev);

-- name: UpdateMilestone :exec
UPDATE milestones
SET title = @title, order_index = @order_index, status = @status,
    updated_at = @updated_at, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id;

-- name: SoftDeleteMilestone :execrows
UPDATE milestones
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: SoftDeleteMilestonesByPlan :exec
UPDATE milestones
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE plan_id = @plan_id AND user_id = @user_id AND deleted_at IS NULL;

-- name: UpsertMilestoneLWW :execrows
INSERT INTO milestones (id, plan_id, user_id, title, order_index, status, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @plan_id, @user_id, @title, @order_index, @status, @created_at, @updated_at, @deleted_at, @server_rev)
ON CONFLICT (id) DO UPDATE SET
    plan_id = excluded.plan_id,
    title = excluded.title,
    order_index = excluded.order_index,
    status = excluded.status,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at,
    server_rev = excluded.server_rev
WHERE excluded.updated_at > milestones.updated_at
  AND milestones.user_id = excluded.user_id;

-- name: ListMilestonesChangedSince :many
SELECT * FROM milestones
WHERE user_id = @user_id AND server_rev > @cursor
ORDER BY server_rev;
