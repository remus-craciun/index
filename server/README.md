# server

Backend for a single-user, offline-first productivity app: ad-hoc tasks, AI-generated learning plans, a merged "Today" schedule, and delta sync for the mobile client.

Go, chi, SQLite (`modernc.org/sqlite`, CGO-free, WAL mode), sqlc, JWT, and Gemini structured output.

## Run locally

Run these commands from this `server/` directory.

```sh
cp .env.example .env   # then set JWT_SECRET (openssl rand -hex 32) and GEMINI_API_KEY
go run .               # loads .env automatically; real env vars take priority
go test ./...
```

After editing `internal/db/queries/*.sql` or the migrations, regenerate the query code:

```sh
go tool sqlc generate
```

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `8080` | |
| `DB_PATH` | `/data/app.db` | Put this on a persistent volume |
| `JWT_SECRET` | – | **Required**, at least 32 bytes |
| `GEMINI_API_KEY` | – | Optional; AI endpoints return 503 without it |
| `GEMINI_MODEL` | `gemini-flash-latest` | Any Gemini model that supports structured output |
| `CORS_ORIGINS` | `*` | Comma-separated |
| `ACCESS_TTL` / `REFRESH_TTL` | `15m` / `0` | Go duration syntax. `REFRESH_TTL=0` means refresh tokens never expire |

## Deploying on Coolify (Railpack)

In Coolify, set the application's **Base Directory** to `/server`. `main.go` is at the root of that folder, so Railpack builds it with no extra configuration. Then:

1. Add a persistent storage volume mounted at `/data`.
2. Set `JWT_SECRET` and `GEMINI_API_KEY` as secrets.
3. Point the health check at `GET /healthz`. It returns 503 if the database is unreachable.

Migrations run automatically at startup.

## Auth model

There is exactly one account.

- `GET /api/v1/auth/status` returns `{"has_user": bool}`. The app calls it after the user enters the server address, then shows the registration screen if it's `false` and the login screen if it's `true`.
- `POST /auth/register` only works while no user exists. After that it returns `403 registration_disabled`.
- Login and register return `{access_token, refresh_token, token_type, expires_in}`. Send the access token as `Authorization: Bearer <token>`. When it expires, exchange the refresh token at `POST /auth/refresh`.
- Each login creates a **session** on the server. Refresh tokens carry the session ID and don't expire (unless `REFRESH_TTL` is set), so a login lasts until you sign out. `POST /auth/logout {refresh_token}` revokes the session, and its refresh tokens stop working everywhere. Logout always returns 204.

## API (`/api/v1`, bearer auth unless noted)

| Method | Path | |
|---|---|---|
| GET | `/health` | Public. Returns `{status, database, time}`, or 503 if the DB is down. Also served at `/health` and `/healthz`. |
| GET | `/auth/status` | public |
| POST | `/auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout` | public |
| GET, POST | `/plans` | |
| GET, PATCH, DELETE | `/plans/{id}` | GET returns milestones and tasks nested. DELETE cascades to them. |
| POST | `/plans/{id}/milestones` | |
| PATCH, DELETE | `/milestones/{id}` | DELETE cascades to tasks |
| GET, POST | `/tasks` | filters: `date`, `status`, `milestone_id`, `adhoc=true` |
| PATCH, DELETE | `/tasks/{id}` | |
| GET | `/today?date=YYYY-MM-DD` | Pass the device's local date |
| POST | `/sync` | |
| POST | `/ai/decompose-plan` | `{prompt, start_date?, target_date?, minutes_per_day?, weekdays?}` |
| POST | `/ai/breakdown-task` | `{task_id}` |
| POST | `/ai/revise-plan` | `{plan_id, instruction, today?, minutes_per_day?}`: previews a follow-up request, stores nothing. Keeps the plan's weekdays unless the instruction changes them |
| POST | `/plans/{id}/apply-revision` | `{revision, start_date?, minutes_per_day?}`: stores a previewed revision |

How the endpoints behave:

- **Creates accept an optional client-generated `id`** (UUID), so rows created offline keep their IDs.
- **PATCH is partial.** Sending `null` clears a nullable field, and omitting a field leaves it unchanged.
- **Deletes are soft.** They set `deleted_at`.
- **Errors** look like `{"error": {"code", "message"}}`.
- **`/today`** lists pending tasks scheduled on or before the date, ordered overdue first, then learning tasks, then ad-hoc ones. Tasks completed or skipped on that date come after them. Items carry `overdue`, `milestone_title`, `plan_id` and `plan_title`.
- **`/ai/decompose-plan`** asks Gemini for a plan (JSON schema enforced). The prompt names the `weekdays` the learner can work (a bitmask, Monday = 1 … Sunday = 64; omitted means every day) and sizes the total minutes to those days only. Tasks are then packed from `start_date` onto those weekdays, filling up to `minutes_per_day` each day. It saves the plan and returns it nested.
- **`/ai/revise-plan`** sends the current plan (with IDs, statuses and dates), the days the learner can work, and the request to Gemini, then reconciles the answer. It returns `{revision, summary, changes, minutes_per_day, weekdays}`. `weekdays` stays as stored on the plan unless the request changes which days they can work. Nothing is stored until the client posts `revision` to **`/plans/{id}/apply-revision`**. Applying re-spreads pending tasks over those weekdays from `start_date` and saves the mask. Whichever endpoint receives it, a revision can't edit or remove completed or skipped tasks: dropped ones go back to their milestone, and IDs that don't belong to the plan become new items. The daily budget defaults to the plan's busiest scheduled day.
- **`/ai/breakdown-task`** replaces a task with 2–8 subtasks. They inherit its milestone and date, and the original task is soft-deleted.

## Sync contract

```jsonc
// POST /api/v1/sync
{ "cursor": 42,              // from the previous response; 0 on first sync
  "changes": {               // local rows modified since the last sync (full rows)
    "learning_plans": [...], "milestones": [...], "recurrences": [...], "tasks": [...] } }

// 200
{ "cursor": 57, "reset": false,
  "changes": { "learning_plans": [...], "milestones": [...], "recurrences": [...], "tasks": [...] } }
```

- **Conflicts** are last-write-wins on `updated_at`. Any RFC 3339 timestamp is accepted and normalised to UTC milliseconds.
- **Deletes** travel as rows with `deleted_at` set (tombstones).
- **Response rows** are every row changed since `cursor`, plus the server's copy of any pushed row that lost a conflict. Apply them locally and store the new `cursor`.
- **The cursor** is a server-side revision counter, not a timestamp, so device clock skew cannot cause missed rows.
- **`reset: true`** means the client's cursor was ahead of the server (for example after a restore). The response then holds a full snapshot, and the client should replace its local data with it.
- **Push order:** parents are applied before children (plans, milestones, recurrences, tasks). A milestone must reference a known plan, and a task a known milestone and recurrence, or the whole sync fails with `400`.
- **Recurrences** (routines) are rules. `frequency` is `daily` (every `repeat_interval` days from `start_date`), `weekly` (on the `weekdays` bitmask, every `repeat_interval` weeks counted from the Monday-based week containing `start_date`) or `monthly` (on `month_day` 1–31, falling on the last day in shorter months, every `repeat_interval` months counted from `start_date`'s month; `month_day` is required for monthly and ignored otherwise). Both default to weekly, every 1 week. `weekdays` is a bitmask (Monday = 1 … Sunday = 64, so 127 = every day and 31 = weekdays). There are also optional `start_time`/`end_time` (`HH:MM`), `reminder_minutes`, `start_date`, `end_date` and `status` (`active` or `paused`). The server stores them but doesn't expand them. Clients generate the occurrences as tasks with `recurrence_id` set and a deterministic ID derived from the recurrence and the date. Only occurrences a user touched (completed, edited, deleted) are ever pushed.
- **Task fields:** `start_time`/`end_time` (`HH:MM`, local time, end after start), `reminder_minutes` (minutes before the start; 0–10080), and `completed_at` (set when a task is completed or skipped, cleared when reopened).
- **Batch size:** at most 5000 rows per request.
