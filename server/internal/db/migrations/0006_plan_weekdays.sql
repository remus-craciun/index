-- +goose Up
-- Days an AI plan may be scheduled on. Monday = 1 … Sunday = 64, 127 = every day.
-- Sync updates do not touch this column; only plan generation and revision do.
ALTER TABLE learning_plans ADD COLUMN weekdays INTEGER NOT NULL DEFAULT 127 CHECK (weekdays BETWEEN 1 AND 127);

-- +goose Down
ALTER TABLE learning_plans DROP COLUMN weekdays;
