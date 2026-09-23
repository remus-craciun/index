# mobile

Flutter client (Android for now). Everything works offline: the UI reads only from the local Drift database, and a background sync engine keeps it in step with the server.

## Run

```sh
flutter pub get
dart run build_runner build        # after changing tables or @riverpod providers
flutter run                        # needs an Android device/emulator (Android SDK)
flutter run -d chrome              # web; enter localhost:8080 as the server
```

On web, SQLite runs as WebAssembly. `web/sqlite3.wasm` and `web/drift_worker.js` come from the [drift release](https://github.com/simolus3/drift/releases) matching the `drift` version in `pubspec.lock`. Download both again whenever you upgrade drift.

The first launch asks for the server address. Bare IPs use `http://` and domains use `https://`; type a scheme to override. The app checks `GET /api/v1/health`, then shows registration if the server has no account yet, or login if it does.

## Tests

```sh
flutter test                       # unit + widget tests (e2e is skipped)

# End-to-end against a real, fresh server:
(cd ../server && JWT_SECRET=$(openssl rand -hex 32) DB_PATH=/tmp/e2e.db PORT=18090 go run .)
INDEX_E2E_URL=http://localhost:18090 flutter test test/e2e
```

The e2e test runs two simulated devices against the server. It covers registration lockout, transparent token refresh, push/pull, completion and deletion propagating between devices, last-write-wins conflicts and plan cascade deletes.

## Layout

```
lib/
  core/
    db/            Drift tables and database (local mirror + `dirty` flag)
    network/       Dio API client, auth-refresh and retry interceptors, token storage
    notifications/ reminder planning + local notification scheduling (Android)
    session/       server address + login state (drives routing)
    sync/          SyncEngine (push/pull protocol) and SyncController (scheduling)
    ui/            theme, formatting, shared widgets
  features/
    auth/          server setup, login/registration
    today/         merged daily schedule
    tasks/         inbox, task tile, task editor; TasksRepository
    routines/      repeating tasks: RoutinesRepository + occurrence generator, editor
    calendar/      month view with routine previews
    history/       completed tasks review
    plans/         plan list/detail, AI plan generator; PlansRepository
    ai/            AiRepository (decompose-plan, breakdown-task)
    settings/
    shell/         bottom navigation, sync indicator
    repositories.dart   Riverpod providers for repositories and reactive queries
  router.dart      go_router with session-based redirects
```

## How offline sync works

- **Local writes:** every write goes to Drift first, stamps `updated_at` and sets `dirty = true`. The edit stamp is always later than the row's previous stamp, so an edit wins last-write-wins even if the phone's clock is behind.
- **What a sync does:** it pushes all dirty rows, parents before children, together with the stored `cursor`. It then merges the response. A server row overwrites the local one unless the local row has an even newer unsynced edit, for example one made while the request was in flight.
- **Deletes:** deletes are tombstones. After the server acknowledges them, they're removed from the device.
- **When it runs:** at startup, 1.5 s after local edits, when the app resumes, when connectivity returns, every 5 minutes, and on pull-to-refresh or the cloud icon.
- **Sign-out:** local data is kept on sign-out. It's wiped only when you connect to a different server, and the app asks first.
- **AI features:** these need a connection. The results are written to Drift straight away.

## Routines and reminders

- **Routines** repeat every N days (daily), on chosen weekdays every N weeks (weekly, for example every 2 weeks on Monday and Thursday), or on a day of the month every N months (monthly; the 31st means the last day in shorter months). Any one-off task can be turned into one from its editor's Repeat row. They can have a time window (for example work 08:00–17:00 on weekdays). The app generates their occurrences as normal tasks for the next 60 days. The calendar shows previews beyond that.
  - Every device generates the same occurrences, with the same IDs.
  - An occurrence you haven't touched stays on the device and isn't synced.
  - Completing, editing or deleting an occurrence syncs it like any task.
- **Editing a routine** updates upcoming occurrences you haven't changed individually. Pausing it or removing a weekday drops those untouched occurrences. Deleting it also removes upcoming ones you edited, and keeps completed ones in History.
- **Missed occurrences** of a routine don't pile up as overdue on Today.
- **Reminders** fire the chosen number of minutes before a task's start time. Tasks without a start time count from 09:00, which you can change in Settings.
  - Each Android device schedules local notifications for the next 14 days from its own database, so they work offline.
  - With the exact-alarm permission they fire on time; without it Android may delay them a few minutes.
  - There are no notifications on web.
