-- name: ListTasks :many
SELECT * FROM tasks
WHERE user_id = @user_id
  AND deleted_at IS NULL
  AND (sqlc.narg(scheduled_date) IS NULL OR scheduled_date = sqlc.narg(scheduled_date))
  AND (sqlc.narg(status) IS NULL OR status = sqlc.narg(status))
  AND (sqlc.narg(milestone_id) IS NULL OR milestone_id = sqlc.narg(milestone_id))
  AND (NOT CAST(@adhoc_only AS BOOLEAN) OR milestone_id IS NULL)
ORDER BY scheduled_date IS NULL, scheduled_date, created_at;

-- name: ListTasksByPlan :many
SELECT t.* FROM tasks t
JOIN milestones m ON m.id = t.milestone_id
WHERE m.plan_id = @plan_id AND t.user_id = @user_id AND t.deleted_at IS NULL
ORDER BY m.order_index, t.scheduled_date IS NULL, t.scheduled_date, t.created_at;

-- name: GetTask :one
SELECT * FROM tasks
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: GetTaskIncludingDeleted :one
SELECT * FROM tasks
WHERE id = @id AND user_id = @user_id;

-- name: InsertTask :exec
INSERT INTO tasks (id, user_id, milestone_id, recurrence_id, title, notes, scheduled_date, start_time, end_time,
                   estimated_minutes, reminder_minutes, status, completed_at, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @user_id, @milestone_id, @recurrence_id, @title, @notes, @scheduled_date, @start_time, @end_time,
        @estimated_minutes, @reminder_minutes, @status, @completed_at, @created_at, @updated_at, NULL, @server_rev);

-- name: UpdateTask :exec
UPDATE tasks
SET milestone_id = @milestone_id, title = @title, notes = @notes, scheduled_date = @scheduled_date,
    start_time = @start_time, end_time = @end_time, estimated_minutes = @estimated_minutes,
    reminder_minutes = @reminder_minutes, status = @status, completed_at = @completed_at,
    updated_at = @updated_at, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id;

-- name: SoftDeleteTask :execrows
UPDATE tasks
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE id = @id AND user_id = @user_id AND deleted_at IS NULL;

-- name: SoftDeleteTasksByMilestone :exec
UPDATE tasks
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE milestone_id = @milestone_id AND user_id = @user_id AND deleted_at IS NULL;

-- name: SoftDeleteTasksByPlan :exec
UPDATE tasks
SET deleted_at = @now, updated_at = @now, server_rev = @server_rev
WHERE tasks.user_id = @user_id AND tasks.deleted_at IS NULL
  AND tasks.milestone_id IN (SELECT m.id FROM milestones m WHERE m.plan_id = @plan_id);

-- name: UpsertTaskLWW :execrows
INSERT INTO tasks (id, user_id, milestone_id, recurrence_id, title, notes, scheduled_date, start_time, end_time,
                   estimated_minutes, reminder_minutes, status, completed_at, created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @user_id, @milestone_id, @recurrence_id, @title, @notes, @scheduled_date, @start_time, @end_time,
        @estimated_minutes, @reminder_minutes, @status, @completed_at, @created_at, @updated_at, @deleted_at, @server_rev)
ON CONFLICT (id) DO UPDATE SET
    milestone_id = excluded.milestone_id,
    recurrence_id = excluded.recurrence_id,
    title = excluded.title,
    notes = excluded.notes,
    scheduled_date = excluded.scheduled_date,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    estimated_minutes = excluded.estimated_minutes,
    reminder_minutes = excluded.reminder_minutes,
    status = excluded.status,
    completed_at = excluded.completed_at,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at,
    server_rev = excluded.server_rev
WHERE excluded.updated_at > tasks.updated_at
  AND tasks.user_id = excluded.user_id;

-- name: ListTasksChangedSince :many
SELECT * FROM tasks
WHERE user_id = @user_id AND server_rev > @cursor
ORDER BY server_rev;

-- Today: pending tasks due on or before the day, plus tasks already
-- completed or skipped on that day. Tasks in archived or deleted plans
-- are hidden.
-- name: ListToday :many
SELECT
    t.*,
    CAST(t.status = 'pending' AND t.scheduled_date < @day AS BOOLEAN) AS overdue,
    m.title AS milestone_title,
    p.id    AS plan_id,
    p.title AS plan_title
FROM tasks t
LEFT JOIN milestones m ON m.id = t.milestone_id
LEFT JOIN learning_plans p ON p.id = m.plan_id
WHERE t.user_id = @user_id
  AND t.deleted_at IS NULL
  AND t.scheduled_date IS NOT NULL
  AND (
        (t.status = 'pending' AND t.scheduled_date <= @day)
     OR (t.status <> 'pending' AND t.scheduled_date = @day)
  )
  -- Missed routine occurrences don't pile up as overdue.
  AND (t.recurrence_id IS NULL OR t.scheduled_date = @day)
  AND (t.milestone_id IS NULL OR (m.deleted_at IS NULL AND p.deleted_at IS NULL AND p.status <> 'archived'))
ORDER BY
    t.status <> 'pending',
    overdue DESC,
    t.milestone_id IS NULL,
    t.scheduled_date,
    t.start_time IS NULL,
    t.start_time,
    p.title,
    m.order_index,
    t.created_at;
