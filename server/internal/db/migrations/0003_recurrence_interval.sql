-- +goose Up

-- 'daily':  every repeat_interval days counted from start_date (weekdays ignored).
-- 'weekly': on the weekdays mask, every repeat_interval weeks counted from
--           the Monday-based week containing start_date.
ALTER TABLE recurrences ADD COLUMN frequency TEXT NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('daily', 'weekly'));
ALTER TABLE recurrences ADD COLUMN repeat_interval INTEGER NOT NULL DEFAULT 1 CHECK (repeat_interval BETWEEN 1 AND 365);

-- +goose Down
ALTER TABLE recurrences DROP COLUMN repeat_interval;
ALTER TABLE recurrences DROP COLUMN frequency;
