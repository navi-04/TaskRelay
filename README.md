# TaskRelay

A task-completion tracker: a daily task list with durations, start and end times and limits, recurring tasks, lock-screen alarms, streaks, a calendar and a day-by-day sheet. On Android it can also keep distracting apps closed until your tasks are done (an optional app blocker; its settings stay on the phone).

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

## Releasing the Android app

1. Copy `app/android/key.properties.example` to `app/android/key.properties` and fill in the two passwords of the upload keystore (`app/upload-keystore.jks`, key alias `upload`). Both files are git-ignored (`*.jks`, `key.properties`); never commit them.
2. `cd app && flutter build appbundle --release` (a release bundle refuses to build without `key.properties`, so it can never be signed with the debug key by mistake). Raise the number after `+` in `app/pubspec.yaml` for every upload.
3. Play Console texts (listing, permission and Accessibility declarations, data safety) are in [`docs/`](docs).

## Database & deploys

- Schema changes are plain SQL files in `web/db/migrations/` (additive only, never edit one that has been applied).
- `npm run build` applies pending migrations on a **Vercel production** build, before the new code can go live (previews and local builds never touch the database). Apply them by hand with `cd web && npm run migrate`.
- Contract fixtures in `web/test/fixtures/` are generated from the real API output and compared by `npm test`; after an intentional API change run `UPDATE_FIXTURES=1 npm test` and review the diff. The Android app parses the same files in its tests.

## Secrets

`.env*` files are git-ignored (only `*.example` templates are tracked). The Turso token lives only on the server (`web/.env.local` and the Vercel project settings), never in the phone app.
