# Permissions — TaskRelay (Android)

TaskRelay 2.0 is Android + web only (iOS is out of scope). The list below is exactly what
[`app/android/app/src/main/AndroidManifest.xml`](../app/android/app/src/main/AndroidManifest.xml) declares; the debug-only manifest adds
plain-HTTP access to the local dev server and is not part of release builds.

## What the app asks for, and why

| Permission | Granted | Why TaskRelay needs it |
|---|---|---|
| `INTERNET` | Automatically | Sign in, load and save tasks, and sync the alarm schedule with the TaskRelay server. |
| `POST_NOTIFICATIONS` | Runtime prompt (Android 13+) | Show task reminders, the daily/end-of-day reminder and "Missed" notices. |
| `SCHEDULE_EXACT_ALARM` | User turns it on in system settings (Android 12+) | Make the daily and end-of-day reminders arrive on the exact minute (`setExactAndAllowWhileIdle`). **Task alarms do not depend on it**: they use `AlarmManager.setAlarmClock`, which Android exempts from this permission, so they ring on the minute even when it is off. Without it only the reminders fall back to "approximately on time". |
| `USE_FULL_SCREEN_INTENT` | Automatic; user-revocable on Android 14+ | Show the alarm screen over the lock screen with **Complete / Snooze 10 min / Dismiss**, so an alarm can be answered without unlocking. |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Automatically | While an alarm rings, a foreground service of type `mediaPlayback` plays the looping alarm sound and vibration. It stops by itself after 3 minutes (then posts "Missed: <task>"). |
| `VIBRATE` | Automatically | Vibrate with the alarm and with reminders. |
| `WAKE_LOCK` | Automatically | Keep the CPU awake for the few seconds it takes to start the alarm screen and sound. |
| `RECEIVE_BOOT_COMPLETED` | Automatically | Re-arm every alarm after a reboot, app update, clock change or time-zone change. It never starts the alarm service from the boot broadcast (Android 15 forbids it). |

No other permission is requested: no location, contacts, camera, microphone, storage, or advertising ID.

### Removed since 1.x (do not re-add without a reason)

| Removed | Why it is gone |
|---|---|
| `SYSTEM_ALERT_WINDOW` | The overlay was replaced by a normal full-screen-intent activity. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Not needed: alarms are `setAlarmClock` alarms, which Doze lets through. Also a Play policy risk. |
| `DISABLE_KEYGUARD` | The alarm activity uses `showWhenLocked` / `turnScreenOn` instead. |
| `USE_EXACT_ALARM` | Only for apps whose *primary* purpose is alarms/calendar; `SCHEDULE_EXACT_ALARM` with an honest fallback is the safer fit for a task app. |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Replaced by the accurate `mediaPlayback` type. |

## Runtime permission flow

Nothing is requested at launch, and a new user with no alarms is never asked for anything.

1. **When the user saves a task that has an alarm or reminder**, the app explains and offers the first permission that is missing, in this order:
   notifications (`POST_NOTIFICATIONS`), then the full-screen alarm (`USE_FULL_SCREEN_INTENT`, Android 14+, opens its system page if it was revoked).
   Each step starts with a plain-language reason and a **Not now** button.
2. **Once alarms are armed and one of those is still missing**, a dismissible banner ("Allow “…” so your reminders and alarms can ring") appears at the top
   of the app, with **Fix** for the next missing permission. It does not appear when the schedule has no alarms.
3. **Profile → Alarm health** always shows when the schedule last synced, how many alarms are armed and through which date, what is next, and the
   state of all three permissions, including the optional **Exact reminder times** (`SCHEDULE_EXACT_ALARM`), which is never nagged about because task
   alarms do not need it.

If the user declines, nothing is lost and no data is touched; the alarms that cannot ring are simply the ones Android will not allow.

## Declarations for Play Console

These are the answers to paste into the Play Console forms. Submitting them is a Play Console action, so it is left to the developer.

**Full-screen intent (`USE_FULL_SCREEN_INTENT`)**

> TaskRelay is a task manager whose core feature is user-scheduled alarms (for example "Take medication at 08:00"). When an alarm the user set fires
> while the device is locked, the app shows a full-screen alarm screen with Complete, Snooze and Dismiss buttons so the user can respond without
> unlocking. The permission is used only for alarms the user created, never for advertising, promotions, or any other purpose.

**Foreground service type `mediaPlayback`**

> The service plays the alarm sound (and vibration) that the user set for a task. It runs only while an alarm is ringing and stops itself after at
> most 3 minutes or as soon as the user completes, snoozes or dismisses the alarm.

**Exact alarms (`SCHEDULE_EXACT_ALARM`)**

> Used only so the user's daily and end-of-day reminder notifications arrive on the minute they chose. Task alarms are scheduled with
> `setAlarmClock`, which does not need this permission. If the user denies it, the app still works and those reminders may arrive a little late.

## Notes

- `allowBackup="false"`: the session token is wrapped by an AndroidKeyStore key that cannot survive a restore, so app data is never backed up or restored
  (see `res/xml/backup_rules.xml` and `res/xml/data_extraction_rules.xml`).
- Release builds do not allow plain-HTTP traffic. Debug builds do, only so a phone can reach a dev server over `adb reverse`.
- No test compares the manifest with this file, so when the manifest changes, update this file in the same commit.
