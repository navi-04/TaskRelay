# Android native layer (Kotlin)

Everything that must keep working when the Flutter UI is not running lives in Kotlin under
`app/android/app/src/main/kotlin/com/naveenraj/taskrelay/`: scheduling alarms, ringing them, completing a task from the lock
screen / a notification / the widget, the background sync with the server and the home-screen widget. Dart talks to it through one
MethodChannel (below). The native UI is strictly black and white (greys only): white background + black text, night mode inverted.

## Architecture

```
Dart  <-- MethodChannel com.naveenraj.taskrelay/native -->  AlarmChannel
                                                               |
 SessionStore (AndroidKeyStore AES-GCM)                        |
 SyncWorker (WorkManager) --> SyncClient --> FeedPlanner --> AlarmScheduler --> AlarmManager
                                  |                              |                   |
                          ActionLog (replay)              AlarmStore (JSON)     AlarmReceiver
                                  |                                                  |
                            TodayCache <-- AlarmActions.complete <-- AlarmActivity / ActionReceiver / WidgetActionReceiver
                                  |                                   AlarmService (ring)        Notifications
                         TodayWidgetProvider / TodayWidgetService
```

| File | Role |
| --- | --- |
| `AlarmChannel.kt`, `MainActivity.kt`, `LaunchState.kt`, `DartBridge.kt` | The channel, share / widget-launch intents, native -> Dart calls (only while the engine exists). |
| `SessionStore.kt` | Base URL + bearer token. Token encrypted with an AES-256-GCM key in the AndroidKeyStore (alias `taskrelay_session`), stored as `base64(iv\|ciphertext)` in the private prefs file `taskrelay_session`. A decrypt failure = signed out, prefs cleared. Excluded from backup. |
| `Feed.kt`, `FeedPlanner.kt` | PURE: parse `GET /api/v1/sync` and turn it into entries. No clocks, no Android, deterministic. |
| `AlarmDiff.kt`, `AlarmStore.kt`, `AlarmScheduler.kt` | Diff by key, nearest-100 arming, the persisted plan + sync state, all AlarmManager calls under one process-wide lock. |
| `ActionLog.kt`, `ReplayPolicy.kt` | Append-only log of completes not yet on the server, and the PURE decision table for replaying it. |
| `SyncClient.kt`, `SyncWorker.kt`, `Http.kt` | One sync = replay log, tz PATCH, GET /sync, plan, arm, cache, widget. `HttpURLConnection`, 15 s timeouts, no redirects. |
| `AlarmReceiver.kt`, `AlarmService.kt`, `AlarmActivity.kt`, `ActionReceiver.kt`, `AlarmActions.kt`, `Notifications.kt` | Fire path, the ring, the lock-screen UI, the ONE Complete path, the single owner of notification channels. |
| `BootReceiver.kt` | Re-arm after boot / app update / clock or zone change / exact-alarm permission change. Never starts `AlarmService`. |
| `TodayCache.kt`, `ReminderText.kt`, `WidgetState.kt`, `TodayWidget*.kt`, `WidgetActionReceiver.kt` | Today's numbers, reminder text composed at fire time, the widget. |

### Entry model

```
Entry { key, kind, taskId?, date (yyyy-MM-dd), localTime (HH:mm), title, triggerMs, origKind? }
kind  = alarm | notification | reminder_daily | reminder_eod | midnight | snooze
key   = <kind>/<taskId or '-'>/<date>[/<hhmm for snooze>]      e.g. alarm/fx-task-gym/2026-11-06
```

* `date` + `localTime` are wall-clock in the device zone, so `triggerMs` can be re-resolved after a timezone change
  (`ZonedDateTime.of(date, time, zone)`: a DST gap shifts forward, an overlap takes the earlier offset). Snoozes are absolute instants.
* `snooze` is native-owned (created by the Snooze action, never sent to the server); `origKind` records whether it rings or notifies.
* `midnight` is a 00:01 local trigger each day: it enqueues a light sync and refreshes the widget. Invisible to the user.
* A PendingIntent is identified by the data URI `taskrelay://alarm/<key>` with a constant request code, so one key = one registration.
  Every PendingIntent also carries the whole entry as extras, so a fire never depends on the store.
* Notification id = `key.hashCode() and 0x3FFFFFFF`.
* Intents that open `MainActivity` (notification taps, the widget, the system "next alarm" show-intent) are told apart by ACTION, never by a data URI:
  Flutter's default deep-link handling forwards `Intent.getData()` to Dart as route information.

### Planning (`FeedPlanner.plan`)

For each feed alarm: resolve the instant, **drop it if it is not after now** (a past alarm is never moved to tomorrow), drop it if the
(taskId, date) has a pending `complete` in the ActionLog. Add `reminder_daily` / `reminder_eod` for the next 14 days from the settings
and one `midnight` per day. Keep native snoozes unless the feed shows them obsolete (it covers the date and no longer lists the task
open, or a complete is pending). Alarms dated after `window.covered_until` (the server caps the list at 200) are **carried over from the
previous plan instead of cancelled for being absent**. Sorted by time, capped at 400.

### Arming (`AlarmScheduler`)

* `replaceAll(entries)`: diff against the stored set by key. Unchanged (same `triggerMs` + title and still registered with the OS) = no-op;
  disappeared keys are cancelled; new / changed keys are armed. Only the **nearest 100** future entries are armed (Android allows ~500
  alarms per app); `rearmFromStore()` tops the set up after boot, after every fire and after every apply.
* Task entries use `setAlarmClock` (show-intent opens `MainActivity`). Reminders and `midnight` use `setExactAndAllowWhileIdle`, so they
  do not put a fake "next alarm" in the status bar. Without exact-alarm permission (API 31+) everything falls back to
  `setAndAllowWhileIdle` and `exactAlarmAllowed=false` is reported; a `SecurityException` never loses an entry.
* It never touches `AlarmService`: replacing the plan cannot stop an alarm that is ringing.
* `armedCount`, `armedThrough` and `nextAlarmMs` count task entries only (alarm / notification / snooze), not reminders or midnight triggers.

### Fire path

`AlarmReceiver` always forgets the fired entry and re-arms from the store afterwards.

| kind | what happens |
| --- | --- |
| `alarm` (or snooze of an alarm) | Start `AlarmService` (foreground, type `mediaPlayback`): looping sound + vibration + a full-screen-intent notification that opens `AlarmActivity` over the lock screen. If the service cannot start, a full-screen-intent heads-up on `alarm_critical_v5` (its own alarm sound, repeated) takes over. |
| `notification` (or snooze of one) | Plain heads-up on `reminders` with **Done** and **Snooze 10 min** actions. |
| `reminder_daily` | "Good morning" / "`<planned>` tasks today · Top 3: a, b, c · `<n>` overdue", composed at fire time from `TodayCache`. |
| `reminder_eod` | "Today: `<done>` of `<planned>` done · Nice work!" or "· `<n>` left". |
| `midnight` | Enqueue a one-time sync, refresh the widget. |

`AlarmService`: one ring slot; a second start updates the notification and never creates a second `MediaPlayer`; auto-stops after 3 minutes and
posts "Missed: `<title>`" on `missed`; a replaced ring also posts "Missed". Actions: Complete, Snooze 10 min, Dismiss (all `PendingIntent`s carry
every extra). The alarm screen swallows Back through an `OnBackPressedDispatcher` callback (works with predictive back on Android 13-16).
There is no overlay window and no `SYSTEM_ALERT_WINDOW`.

### One Complete path - `AlarmActions.complete(ctx, key, taskId, date)`

1. append `taskId|date|complete|<tap epoch ms>` to `filesDir/alarm_actions.log` (fsync under a lock) - nothing after this line can lose the tap
2. stop the ring / remove the notification for that key (and for that task occurrence)
3. mark the task done in `TodayCache` (+ pending overlay) and cancel the task's other armed alarms for that day
4. refresh the widget
5. `SyncWorker.enqueueOnce` (REPLACE, 2 s delay, so bursts coalesce)
6. `onActionsChanged` to Dart if the engine is alive

**Dismiss** only stops (no log, no server call, no data change). **Snooze** stops the ring and arms a local `snooze` entry 10 minutes ahead.
The same path serves the alarm screen, the notification buttons and the widget rows; nothing broadcasts to `MainActivity` and nothing toggles.

### Sync (`SyncClient.runOnce`, one at a time, shared by the worker and `syncNow`)

1. Replay every ActionLog line: `PUT /api/v1/tasks/{id}/days/{date}` `{"status":"done","completed_at":"<tap ISO-8601 UTC>"}`. `ReplayPolicy`:
   2xx, 404, 422 and other 4xx -> remove the line; 400 `invalid_time` -> retry once without `completed_at`; 401 -> stop, keep the log;
   426 -> stop all sync; 429 -> keep, retry after `Retry-After`; 5xx / I/O error -> keep and retry.
2. If the device zone differs from the server's last known zone, `PATCH /api/v1/me {"timezone": ...}` BEFORE the feed, once per difference.
3. `GET /api/v1/sync?days=14` with `If-None-Match`. 304 re-plans from the store (and tops the reminder horizon up). A feed older than the one
   already applied is ignored.
4. plan -> `AlarmScheduler.replaceAll` -> `TodayCache` (the unacked completes are re-applied on top) -> etag / settings / `lastSyncMs` -> widget.

Headers: `Authorization: Bearer <token>`, `X-App-Version: <versionName>`, `User-Agent: TaskRelay-Android/<versionName>`.
Error codes reported to Dart: `unauthorized | upgrade_required | rate_limited | network | server | not_signed_in`.
After a 426 no sync is attempted until the app version changes.

Scheduling: `sync-periodic` (45 min, flex 15 min, network required, KEEP), `sync-once` (REPLACE, 2 s delay, network required, exponential
backoff from 30 s), `sync-retry` (429 with `Retry-After`).

### Reboot, clock and zone changes (`BootReceiver`)

`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET`, `TIMEZONE_CHANGED`, `SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED`: wall-clock entries are
re-resolved in the new zone, alarms / notifications whose time passed in the last 6 hours while the device was off become a plain
"Missed: `<title>`" notification, everything is re-armed (nearest 100), the periodic sync is ensured and a one-time sync is enqueued.
It never starts `AlarmService` (Android 15 forbids a `mediaPlayback` foreground service from `BOOT_COMPLETED`).

### Widget

`TodayWidgetProvider` + `TodayWidgetService` read `TodayCache` (date, planned, done, overdue, top titles, up to 25 tasks, pending overlay).
Header "Today", `<done>/<planned>`, a "+" button, rows with a checkbox glyph (done rows struck through). A row tap is a template broadcast to
`WidgetActionReceiver` -> the one Complete path; a done row cannot be un-ticked, tapping it opens the app. "+" opens `MainActivity` with
`open_add=true` (Dart reads it with `getLaunchAction`). Cache date != today shows "Open TaskRelay to refresh"; signed out shows
"Sign in to TaskRelay". Refreshed after every sync, at the `midnight` entry, on timezone change and after every Complete.

## MethodChannel contract: `com.naveenraj.taskrelay/native`

Results are plain maps / lists / strings / bools / numbers. Long operations run off the main thread.

| Dart -> native | Result |
| --- | --- |
| `getSession` | `{baseUrl, token}` or `null` |
| `setSession({baseUrl, token})` | `true` (stores it, schedules the periodic sync, enqueues a one-time sync). `baseUrl` must be http(s). |
| `clearSession` | `true`: cancels all work, every armed alarm / reminder / snooze, clears AlarmStore, ActionLog, TodayCache, notifications, refreshes the widget |
| `syncNow` | `{ok, notModified, error?, errorCode?, armedCount, armedThrough?, syncedAtMs}`; full sync, replies when done (30 s overall timeout -> `errorCode: network`) |
| `requestSync` | `true` (enqueue `sync-once`, returns immediately) |
| `getSyncStatus` | `{signedIn, lastSyncMs?, armedCount, armedThrough?, nextAlarmMs?, pendingActions, lastError?, lastErrorCode?, exactAlarmAllowed, notificationsAllowed, fullScreenIntentAllowed}` |
| `getPermissionStatus` | `{notifications, exactAlarm, fullScreenIntent}` (exactAlarm true below API 31, fullScreenIntent true below API 34) |
| `requestNotificationPermission` | `bool`, replies only after the user answers (true below API 33) |
| `openExactAlarmSettings`, `openFullScreenIntentSettings`, `openNotificationSettings` | `true` |
| `getTimeZone`, `getAppVersion` | IANA id, `versionName` |
| `getInitialShare` | `{subject?, text?}` or `null`, consumed once, text capped at 20,000 chars |
| `getLaunchAction` | `"add"` or `null`, consumed once |
| `refreshWidget` | `true` |

| native -> Dart (only while the engine exists) | Arguments |
| --- | --- |
| `onShare` | `{subject, text}` - a new `ACTION_SEND` while running. If Dart does not handle it, the share stays available to `getInitialShare`. |
| `onActionsChanged` | none - a Complete was logged from the lock screen / notification / widget |
| `onSyncFinished` | `{ok, errorCode?}` |

Note for Dart: the widget's "+" while the app is already running arrives as a new intent; there is no push for it, so call `getLaunchAction`
on startup **and** whenever the app resumes.

## Build / R8 / backup

* Release builds run R8 (the Flutter Gradle plugin enables minify + resource shrinking and passes `app/proguard-rules.pro` automatically).
  `proguard-rules.pro` keeps `com.naveenraj.taskrelay.**`. Keep `build/app/outputs/mapping/release/mapping.txt` for every release.
* `android:allowBackup="false"` plus `xml/data_extraction_rules.xml` / `xml/backup_rules.xml`: the keystore-wrapped session is never restored.
* Debug builds allow cleartext (`src/debug/AndroidManifest.xml`) so the app can reach `http://127.0.0.1:3000` through `adb reverse tcp:3000 tcp:3000`.
* Unit tests (JVM, no device): `cd app/android && ./gradlew :app:testDebugUnitTest` (`FeedPlannerTest` parses the real `web/test/fixtures/sync.json`).
  `gradlew` is git-ignored and generated by Flutter on the first `flutter build`; any Gradle 8.14 works too (`gradle :app:testDebugUnitTest`).

## Known limits

* **Doze / App Standby can stretch the 45-minute periodic sync to hours.** Alarms that are already armed with `AlarmManager` still ring on
  time (they are `setAlarmClock` alarms), but a task added on another device only reaches this phone at the next sync (or the next app open /
  midnight trigger). Without network everything already planned keeps ringing (alarms for the feed window, plus reminders planned up to 14 days ahead); new
  entries are only created by a successful sync.
* Only the nearest 100 entries are armed; entries beyond that wait in the store and are armed as time passes.
* Without the exact-alarm permission (Android 12+; denied by default on Android 14+) alarms use `setAndAllowWhileIdle` and can be late by minutes.
  `getSyncStatus.exactAlarmAllowed` tells the UI to ask for it.
* If the OS refuses to start the foreground service from the background, the alarm falls back to a full-screen-intent heads-up (looping channel
  sound, no custom vibration); with Full-screen-intent permission revoked (Android 14+) it is only a heads-up.
* Force-stopping the app clears every registration (and a force-stopped app receives no `BOOT_COMPLETED`); they come back the next time the app
  is opened, because the store survives and the next apply re-arms every entry the OS no longer holds.
* Sign-out discards completes that were not yet synced.
