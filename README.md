# TaskRelay

A task-completion tracker: a daily task list with durations and limits, recurring tasks, lock-screen alarms, streaks and a calendar.

| Folder | What it is |
|---|---|
| [`app/`](app) | Flutter phone app (Android first). |
| [`web/`](web) | Next.js project on Vercel: the HTTP API, a small web UI, and the Turso (libSQL) database schema. |
| [`docs/`](docs) | Release notes and design notes. |

## Running

```bash
# phone app
cd app && flutter pub get && flutter run

# web / API
cd web && cp .env.example .env.local   # fill in TURSO_DATABASE_URL and TURSO_AUTH_TOKEN
npm install && npm run dev
```

## Database & deploys

- Schema changes are plain SQL files in `web/db/migrations/` (additive only, never edit one that has been applied).
- `npm run build` applies pending migrations on a **Vercel production** build, before the new code can go live (previews and local builds never touch the database). Apply them by hand with `cd web && npm run migrate`.
- Contract fixtures in `web/test/fixtures/` are generated from the real API output and compared by `npm test`; after an intentional API change run `UPDATE_FIXTURES=1 npm test` and review the diff. The Android app parses the same files in its tests.

## Secrets

`.env*` files are git-ignored (only `*.example` templates are tracked). The Turso token lives only on the server (`web/.env.local` and the Vercel project settings), never in the phone app.
