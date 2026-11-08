# Android native layer (Kotlin)

Everything that must keep working when the Flutter UI is not running lives in Kotlin under
`app/android/app/src/main/kotlin/com/naveenraj/taskrelay/`: scheduling alarms, ringing them, completing a task from the lock
screen / a notification / the widget, the background sync with the server, the home-screen widget and the app blocker. Dart talks to
it through one MethodChannel (below). The native UI is strictly black and white (greys only): white background + black text, night mode
inverted (the block screen is always pure black).

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
| `TodayCache.kt`, `ReminderText.kt`, `WidgetState.kt`, `TodayWidget*.kt`, `WidgetActionReceiver.kt` | Today's numbers (and today's timed blocks), reminder text composed at fire time, the widget. |
| `BlockerAccessibilityService.kt`, `BlockerOverlay.kt` | The app blocker: the accessibility service (events, heartbeat, Home) and the block screen. See *App blocker*. |
| `BlockerPolicy.kt`, `BlockerText.kt`, `TimeBlock.kt` | PURE: "should this app be stopped now" (`Decision`), the words on the block screen, the one time-block rule. No Android, no clock. |
| `BlockerConfig.kt`, `BlockerStore.kt`, `InstalledApps.kt`, `BlockerChannel.kt` | The device-local settings (+ normalisation), the app picker's list / icons / protected set, the `blocker*` channel methods. |

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
There is no overlay window and no `SYSTEM_ALERT_WINDOW` (the app blocker's block screen is an accessibility overlay, which needs no permission: see *App blocker*).

### One Complete path - `AlarmActions.complete(ctx, key, taskId, date)`

1. append `taskId|date|complete|<tap epoch ms>` to `filesDir/alarm_actions.log` (fsync under a lock) - nothing after this line can lose the tap
2. stop the ring / remove the notification for that key (and for that task occurrence)
3. mark the task done in `TodayCache` (+ pending overlay) and cancel the task's other armed alarms for that day
4. refresh the widget
5. re-check the app blocker (`BlockerAccessibilityService.reevaluate`): the last open task may just have been done
6. `SyncWorker.enqueueOnce` (REPLACE, 2 s delay, so bursts coalesce)
7. `onActionsChanged` to Dart if the engine is alive

**Dismiss** only stops (no log, no server call, no data change). **Snooze** stops the ring and arms a local `snooze` entry 10 minutes ahead.
The same path serves the alarm screen, the notification buttons and the widget rows; nothing broadcasts to `MainActivity` and nothing toggles.

### Sync (`SyncClient.runOnce`, one at a time, shared by the worker and `syncNow`)

1. Replay every ActionLog line: `PUT /api/v1/tasks/{id}/days/{date}` `{"status":"done","completed_at":"<tap ISO-8601 UTC>"}`. `ReplayPolicy`:
   2xx, 404, 422 and other 4xx -> remove the line; 400 `invalid_time` -> retry once without `completed_at`; 401 -> stop, keep the log;
   426 -> stop all sync; 429 -> keep, retry after `Retry-After`; 5xx / I/O error -> keep and retry.
2. If the device zone differs from the server's last known zone, `PATCH /api/v1/me {"timezone": ...}` BEFORE the feed, once per difference.
3. `GET /api/v1/sync?days=14` with `If-None-Match`. 304 re-plans from the store (and tops the reminder horizon up). A feed older than the one
   already applied is ignored.
4. plan -> `AlarmScheduler.replaceAll` -> `TodayCache` (the unacked completes are re-applied on top; `today.blocks` is stored too) -> etag / settings / `lastSyncMs` -> widget.
5. Whatever the outcome: `onSyncFinished` to Dart, then `BlockerAccessibilityService.reevaluate` (the app blocker re-checks what is in front).

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

`TodayWidgetProvider` + `TodayWidgetService` read `TodayCache` (date, planned, done, overdue, top titles, up to 25 tasks, pending overlay; the
cache also holds today's timed `blocks`, up to 50, which only the app blocker reads).
Header "Today", `<done>/<planned>`, a "+" button, rows with a checkbox glyph (done rows struck through). A row tap is a template broadcast to
`WidgetActionReceiver` -> the one Complete path; a done row cannot be un-ticked, tapping it opens the app. "+" opens `MainActivity` with
`open_add=true` (Dart reads it with `getLaunchAction`). Cache date != today shows "Open TaskRelay to refresh"; signed out shows
"Sign in to TaskRelay". Refreshed after every sync, at the `midnight` entry, on timezone change and after every Complete.

## App blocker

An optional focus feature. The user picks "distraction" apps and TaskRelay stops them from being used in one of three ways (modes, below):
until the day's tasks are done, only outside the time blocks of today's tasks, or only inside chosen "use times". It is **device-local**: the
settings (`BlockerConfig`) live in the private prefs file `taskrelay_blocker`, are never sent to the server, are excluded from backup
(`backup_rules.xml`, `data_extraction_rules.xml`) and are wiped by `clearSession`. The list of installed apps and their icons only travel to the
Flutter UI on the same device.

```
Dart  -- blocker* channel methods -->  BlockerChannel --> BlockerStore (prefs "taskrelay_blocker", JSON)
                                            '----------> InstalledApps (picker list, icons, protected set)

a window comes to the front --> BlockerAccessibilityService --> BlockerPolicy.decide(config, TodayCache, now, zone)   (PURE)
                                        |                                      |
                       Decision.blocked +--> BlockerOverlay (black screen) --100 ms--> performGlobalAction(HOME)

re-checks: settings saved | SyncClient.runOnce ends | AlarmActions.complete | sign-out | screen on / unlock | 15 s heartbeat | a block or window boundary
```

### What it reads

The server's `GET /api/v1/sync` response carries, besides the existing `today` fields, `today.blocks`: up to 50 of today's tasks that have a start
time, earliest first: `{id, title, start_time "HH:mm", end_time "HH:mm"|null, duration_min, status "open"|"done"}`. `Feed.kt` parses it
(`FeedBlock`), `TodayCache` stores it (`TodayBlock`, `done` boolean). A server or a cache from before blocks existed has none: that reads as an empty list.
`TodayData.withCompleted` (the one Complete path) flips the matching block to done as well (even for a task beyond the first 25 in `tasks`) and keeps
`done` right, so the blocker sees a tap on Complete at once. Everything the blocker needs comes from `Stores.todayCache(app).read()`; it never calls the server itself
(only through `SyncClient`).

**The time-block rule** (`TimeBlock.of`; identical in `web/lib/timeblock.ts` and the Dart app, and all three test suites share the golden cases):

| start | end | block |
| --- | --- | --- |
| set | set | `[start, end)` |
| set | none | `[start, min(start + duration_min, 24:00))`, cut at midnight |
| none | set, or none | no block (an end alone is a deadline, not a slot) |

Minutes since midnight on the wall clock of the device's zone; the end is exclusive; a block with no length (end <= start, zero or negative
duration) is no block; a time that is not exactly `HH:mm` is no block (fail open).

### Modes and the decision (`BlockerPolicy.decide`, PURE)

`decide(config, today: TodayData?, nowMs, zone): Decision`. No Android, no clock, no I/O: everything is injected, so every rule below is a JVM test.

| step | rule |
| --- | --- |
| 1 | `enabled = false` -> allow, `off` |
| 2 | no snapshot, or its `date` is not the device's local date -> allow, `no_data` (**fail open**: missing or stale data never locks the user out) |
| 3 | `left = max(0, planned - done)` (the cache already applies pending local completes); `overdue = count_overdue ? overdue_count : 0` |
| `until_done` | `left + overdue == 0` -> allow `all_done`, else block `tasks_left` |
| `free_time` | an OPEN block that contains now (`start <= now < end`) -> block `task_block`; else allow `free_time` |
| `set_times` | a running open block -> block `task_block` **first** (a use window never overrides a task); else `unlock_when_done` and nothing left -> allow `all_done`; else inside a window whose `days` contain today's ISO weekday (1 = Monday .. 7 = Sunday) -> allow `in_window`; else block `outside_windows` |

A done block never blocks. `Decision { blocked, code, left, overdue, title?, untilMin?, nextStartMin?, nextChangeMin? }`: `title` is the running block's title,
`untilMin` the end of the running block or use window (for `in_window`: `min(window end, next open block start)`), `nextStartMin` the start of the next use
window later today, and `nextChangeMin` the next minute of day at which the clock alone can change the decision (a start or end of an open block, or in
`set_times` of a window that applies today; null if none). Codes: `off | no_data | all_done | free_time | in_window | tasks_left | task_block | outside_windows`.

### Settings (`BlockerConfig`, also the wire shape; snake_case)

```json
{ "enabled": false, "mode": "until_done", "count_overdue": true, "unlock_when_done": false,
  "packages": ["com.example.app"], "windows": [{ "start": "18:00", "end": "20:00", "days": [1, 2, 3, 4, 5] }] }
```

Normalised on load AND on set, never throws: an unknown `mode` becomes `until_done`; `packages` are trimmed, non-blank, distinct, without the protected ones,
at most 60; `windows` need valid `HH:mm` with the end after the start on the same day (no overnight; the latest end is `23:59`), at most 14, sorted by start; `days`
keeps 1..7, and an empty / missing / all-invalid list means every day (stored as `[1..7]`).

### The service (`BlockerAccessibilityService`)

* Registered for **one** event type, `TYPE_WINDOW_STATE_CHANGED`, and it reads **one** thing from it: the package name of the window that came to the front.
  `canRetrieveWindowContent=false`, `canPerformGestures=false`, no `flagRetrieveInteractiveWindows` / `flagReportViewIds`, `notificationTimeout=100`,
  `isAccessibilityTool` not set (TaskRelay is not an accessibility tool). Nothing about the screen, the apps or the titles is ever logged.
* Noise is ignored for "which app is in front": no package, TaskRelay itself, `com.android.systemui`, `android`, the enabled keyboards. Anything else becomes `lastForeground`.
* If `lastForeground` is in `packages` (and the blocker is enabled): `decide(...)`. Blocked -> the block screen goes up **first**, so none of the app shows;
  ~100 ms later `performGlobalAction(GLOBAL_ACTION_HOME)`. (After a successful Home the app's late events are ignored for 1 s so they cannot count as "the user is back in it".)
* The block screen stays until the user taps a button, 12 s pass, or another app comes to the front (a launcher does not count: Home itself brings it up).
* While a blocked-list app stays in front a heartbeat on the main handler re-checks every 15 s, and exactly at `nextChangeMin` (a task block can start while the user
  is scrolling). It stops when the user leaves, the screen turns off or the blocker is switched off. Apart from the 12 s screen timer after a block, nothing runs while no
  blocked-list app is in front: no polling, no foreground service, no wake lock.
* `ACTION_SCREEN_OFF` stops the heartbeat and takes the screen down; `ACTION_USER_PRESENT` (and `ACTION_SCREEN_ON` when there is no lock screen) re-checks the app that is in front again.
* `BlockerAccessibilityService.reevaluate(app)` (safe from any thread, a no-op while the service is not running) is called after: settings saved, `SyncClient.runOnce` ends,
  `AlarmActions.complete` (alarm screen, notification buttons, widget rows all go through it), sign-out. It dismisses the screen when nothing blocks any more and refreshes it otherwise.
* `no_data` because the cache is yesterday's (or missing, while signed in): fail open, and ask for a sync with `SyncWorker.enqueueOnce`, at most once every 5 minutes.
* Every callback is wrapped (`try` / `Log`): nothing throws out of an accessibility callback.

### The block screen (`BlockerOverlay`)

A full-screen window of type `TYPE_ACCESSIBILITY_OVERLAY` (only an enabled accessibility service may add one; **no `SYSTEM_ALERT_WINDOW`**), `FLAG_NOT_FOCUSABLE` (it never takes key
focus: the keyboard and Back keep working underneath; it still gets touches), laid out over the cutout and the system bars. Built in code, strictly black and white: `#000000`
background, white / grey text, a white primary button with black text, outlined secondary buttons, no emoji or symbols (emoji in task titles are stripped, `BlockerText.plain`,
because Android would draw them in colour). It scrolls (large font, landscape), caps its width on tablets, uses `sp` text and has content descriptions on the buttons.

* Title: `<App label> is blocked`.
* Reason: `tasks_left` -> `N tasks left today` (+ ` and M overdue`) and `Next: A, B, C` (up to 3 open tasks from the cache); `task_block` -> `"<title>" runs until HH:mm`;
  `outside_windows` -> `Next use time: HH:mm` or `No use times set for now`.
* Buttons: **Open TaskRelay** (starts `MainActivity`, then dismisses), **Check again** (one `SyncClient.runOnce("blocker")` on `Bg.io`, "Checking..." meanwhile, then it re-evaluates;
  shown unless only the clock can open it: `outside_windows` without `unlock_when_done`), **Close**.

### Protected packages (never blockable)

TaskRelay, `com.android.settings`, `com.android.systemui`, `com.android.phone`, `com.android.dialer`, `com.google.android.dialer`, `com.android.emergency`,
`com.android.contacts`, `com.google.android.contacts`, `com.android.packageinstaller`, `com.google.android.packageinstaller`, `com.google.android.permissioncontroller`,
`com.android.permissioncontroller`, plus what the device says: every app that can be the home screen (`CATEGORY_HOME`), every enabled keyboard and the default dialer.
They are filtered from the picker list, dropped when settings are normalised, and checked once more by the service at the moment of blocking (a launcher installed
after the setting was saved is still safe). `InstalledApps.isProtected(pkg, extra)` is the pure part.

### Channel methods (all in `AlarmChannel`, implemented by `BlockerChannel`)

| Dart -> native | Result |
| --- | --- |
| `blockerGetConfig` | the stored config map (above), normalised |
| `blockerSetConfig(config map)` | the NORMALISED config map that was stored (show this, not what you sent); then the blocker re-checks. The map may also be wrapped as `{config: {...}}`. A non-map argument is an `invalid_argument` error |
| `blockerStatus` | `{serviceEnabled, enabled, hasData, snapshotDate?, decision: {blocked, code, left, overdue, title?, until_min?, next_start_min?, next_change_min?}}`. `serviceEnabled`: our service id is in `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`; `hasData`: a snapshot of TODAY exists (without one the blocker fails open); `decision` is what it would decide right now |
| `blockerListApps` | `[{package, label}]`, launchable apps sorted by label, without the protected ones (runs off the main thread) |
| `blockerAppIcon(package)` | a PNG (`Uint8List`) of at most 96 x 96 px, or `null`; the argument is the package string or `{package}` |
| `blockerOpenAccessibilitySettings` | `true` (opens Android's Accessibility settings) |

### Why an AccessibilityService

It is the only way to learn "an app from my list just came to the front" **without polling, without a foreground service and without a special-access permission**:
`UsageStatsManager` needs the broad usage-access permission plus a polling loop (a permanent foreground service on current Android), and a `SYSTEM_ALERT_WINDOW` overlay cannot tell which
app is behind it. The accessibility event is pushed by the system exactly when a window changes, costs nothing in between, and the same service draws the block screen
(an accessibility overlay needs no overlay permission). The price is the user's explicit switch in Settings -> Accessibility and the Play declaration below.

### Fail-open and its consequences

The blocker only ever blocks on data it can vouch for: today's snapshot, dated today. Never synced, a missed midnight sync, a sign-out, a corrupt cache, a malformed time: nothing is blocked.
After midnight the first sync of the new day re-arms it (the service asks for one). If the foreground app is unknown (the service just connected, or we just sent the user Home) nothing
happens until the next window event.

### Testing

* **JVM** (no device): `BlockerPolicyTest` (every code and mode, the start / end boundaries, done blocks, a task block beating a window, `unlock_when_done`, weekdays incl. Sunday,
  midnight, stale / null data, `count_overdue`, `nextChangeMin`, the real fixture day), `BlockerConfigTest`, `TimeBlockTest` (the golden cases), `TodayBlocksTest` (the real
  `web/test/fixtures/sync.json`, an old cache without blocks, `withCompleted`), `InstalledAppsTest`, `BlockerTextTest`, `BlockerStoreTest`, `BlockerChannelTest`.
* **On a device** (the service, the screen and Home cannot run on the JVM). Switch the service on without the Settings UI:

  ```
  adb shell settings get secure enabled_accessibility_services     # note it: the next command REPLACES the list
  adb shell settings put secure enabled_accessibility_services com.naveenraj.taskrelay/com.naveenraj.taskrelay.BlockerAccessibilityService
  adb shell settings put secure accessibility_enabled 1
  adb shell dumpsys accessibility | grep -i taskrelay               # the service is bound
  adb logcat -s BlockerService BlockerOverlay                       # class names only, never content
  ```

  Then, in the app: sign in, let one sync finish, Profile -> Block distracting apps, pick an app, and check: (1) `until_done` with a task left -> opening the app shows the black screen and lands on the
  launcher; complete the last task elsewhere (the web app, another device), tap **Check again** and the screen goes away, and the app opens next time; (2) `free_time` with a task whose block contains now; (3) `set_times` inside / outside a window;
  (4) **Check again** while offline ("Could not check right now."); (5) Close, Open TaskRelay, 12 s auto-dismiss, rotate to landscape, font size at maximum; (6) Settings, the dialer,
  the launcher and the keyboard are not in the picker; (7) sign out: the list is empty and the screen is gone; (8) lock and unlock while inside a blocked app.
  To switch it off again: `adb shell settings put secure accessibility_enabled 0` (and restore the list you noted).
* **Android 13+ and sideloaded APKs:** the Settings switch is greyed out ("Restricted setting") for an APK that did not come from a store. Open *Settings -> Apps -> TaskRelay ->
  three-dot menu (top right) -> Allow restricted settings*, then switch the service on. Builds installed from Google Play are not restricted.

### Play Console (Accessibility declaration)

The paste-ready texts are in [PERMISSIONS.md](PERMISSIONS.md). What the code guarantees, for the form and the reviewer: one event type (`typeWindowStateChanged`); only the front window's package name is used;
`canRetrieveWindowContent` and `canPerformGestures` are false and no key events, view ids or interactive-window list are requested; `isAccessibilityTool` is not set (the feature is a
focus aid, not an assistive tool, and the answers must say so); the feature is off until the user switches it on, after an in-app disclosure; the blocked-app list and the rules never leave the
device; no `QUERY_ALL_PACKAGES` (a `<queries>` entry lists launchable apps and launchers), no `PACKAGE_USAGE_STATS`, no `SYSTEM_ALERT_WINDOW`, no foreground service for the blocker. The demo video:
disclosure -> Settings -> switch on -> open a blocked app -> block screen -> finish the tasks -> the app opens.

### Known limits

* `notificationTimeout=100` makes Android hold each window event for up to 100 ms and merge a burst of them into the last one, so a blocked app can be visible for a fraction of a
  second before the screen covers it, and a blocked app that opens in the same instant as a system window (whose event wins the merge, and is ignored as noise) can slip through
  until its next window event. Lower it to `0` in `blocker_accessibility_service.xml` if either shows up on a device (every event is then delivered at once).
* After a process restart the service does not know which app is in front until the next window event.
* The block screen covers the status bar and the three-button navigation bar as well (so the notification shade and those buttons cannot be touched while it is up); the buttons, the 12 s
  timeout and Back (which is not trapped) are the way out. Gesture navigation is handled by the system rather than by windows, so it is expected to keep working: check it on a device.
* An app that shows a window under another package name (a floating chat head, a picture-in-picture window) can mislead the "which app is in front" tracking.
* **Open TaskRelay** is a plain `startActivity` from the service, started while the block screen (a visible window the user just tapped) is still up. If a device's background-activity-start rules
  refuse it anyway, the screen just closes and the user opens the app themselves. Not verifiable on the JVM: check it on a real device (Android 10-15 and one OEM skin).
* Tasks changed in the Flutter UI reach the blocker through the sync that follows them (`requestSync`), not directly; a task added on another device only at the next sync, as for alarms.
* Time blocks are wall-clock minutes of the device zone; around a DST change a block is simply the wall-clock range it says.

## MethodChannel contract: `com.naveenraj.taskrelay/native`

Results are plain maps / lists / strings / bools / numbers. Long operations run off the main thread.

| Dart -> native | Result |
| --- | --- |
| `getSession` | `{baseUrl, token}` or `null` |
| `setSession({baseUrl, token})` | `true` (stores it, schedules the periodic sync, enqueues a one-time sync). `baseUrl` must be http(s). |
| `clearSession` | `true`: cancels all work, every armed alarm / reminder / snooze, clears AlarmStore, ActionLog, TodayCache, the app blocker's settings, notifications, refreshes the widget |
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
| `blockerGetConfig`, `blockerSetConfig(config)`, `blockerStatus`, `blockerListApps`, `blockerAppIcon(package)`, `blockerOpenAccessibilitySettings` | The app blocker (device-local settings, status, the app picker, the Accessibility settings screen): see *App blocker -> Channel methods* |

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
* `android:allowBackup="false"` plus `xml/data_extraction_rules.xml` / `xml/backup_rules.xml`: the keystore-wrapped session is never restored, and the blocker's
  prefs (`taskrelay_blocker.xml`) are excluded as well (the blocked-app list is device-local by design).
* Debug builds allow cleartext (`src/debug/AndroidManifest.xml`) so the app can reach `http://127.0.0.1:3000` through `adb reverse tcp:3000 tcp:3000`.
* Unit tests (JVM, no device): `cd app/android && ./gradlew :app:testDebugUnitTest` (`FeedPlannerTest` and `TodayBlocksTest` parse the real `web/test/fixtures/sync.json`;
  regenerating that fixture on the server can change what they expect, e.g. the Gym reminder that is now 17:45 for the 18:00 Gym block).
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
