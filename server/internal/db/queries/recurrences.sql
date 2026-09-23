-- name: GetRecurrenceIncludingDeleted :one
SELECT * FROM recurrences
WHERE id = @id AND user_id = @user_id;

-- name: ListRecurrences :many
SELECT * FROM recurrences
WHERE user_id = @user_id AND deleted_at IS NULL
ORDER BY created_at;

-- name: UpsertRecurrenceLWW :execrows
INSERT INTO recurrences (id, user_id, title, notes, frequency, repeat_interval, weekdays, month_day, start_time, end_time,
                         estimated_minutes, reminder_minutes, start_date, end_date, status,
                         created_at, updated_at, deleted_at, server_rev)
VALUES (@id, @user_id, @title, @notes, @frequency, @repeat_interval, @weekdays, @month_day, @start_time, @end_time,
        @estimated_minutes, @reminder_minutes, @start_date, @end_date, @status,
        @created_at, @updated_at, @deleted_at, @server_rev)
ON CONFLICT (id) DO UPDATE SET
    title = excluded.title,
    notes = excluded.notes,
    frequency = excluded.frequency,
    repeat_interval = excluded.repeat_interval,
    weekdays = excluded.weekdays,
    month_day = excluded.month_day,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    estimated_minutes = excluded.estimated_minutes,
    reminder_minutes = excluded.reminder_minutes,
    start_date = excluded.start_date,
    end_date = excluded.end_date,
    status = excluded.status,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at,
    server_rev = excluded.server_rev
WHERE excluded.updated_at > recurrences.updated_at
  AND recurrences.user_id = excluded.user_id;

-- name: ListRecurrencesChangedSince :many
SELECT * FROM recurrences
WHERE user_id = @user_id AND server_rev > @cursor
ORDER BY server_rev;
