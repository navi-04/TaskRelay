# Mobile Permissions — TaskRelay

This document lists all permissions required by the TaskRelay app on Android and iOS, along with their purpose and when they are requested at runtime.

---

## Android Permissions

Declared in [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml).

| Permission | Required | Runtime Request | Purpose |
|---|---|---|---|
| `POST_NOTIFICATIONS` | Yes (Android 13+) | Yes | Display task reminders and alarm notifications to the user. |
| `SCHEDULE_EXACT_ALARM` | Yes | Yes (Settings redirect) | Schedule task alarms at a precise time (Android 12+). Required for reliable reminders. |
| `USE_EXACT_ALARM` | Yes (Android 13+) | No (auto-granted for clock/alarm apps) | Alternative exact-alarm permission for clock/reminder apps on Android 13+. |
| `VIBRATE` | Yes | No (auto-granted) | Vibrate the device when an alarm or notification fires. |
| `RECEIVE_BOOT_COMPLETED` | Yes | No (auto-granted) | Re-schedule all pending alarms after a device reboot so no reminders are missed. |
| `WAKE_LOCK` | Yes | No (auto-granted) | Keep the CPU running long enough to deliver a notification or alarm while the screen is off. |
| `USE_FULL_SCREEN_INTENT` | Yes | No (auto-granted; user-revocable on Android 14+) | Show the alarm screen over the lock screen without requiring the user to unlock first. |
| `SYSTEM_ALERT_WINDOW` | Yes | Yes (Settings redirect) | Draw the alarm UI over other apps and the lock screen on older Android versions. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Yes | Yes | Ask the user to exempt the app from Doze/battery optimizations so alarms fire on time in the background. |
| `FOREGROUND_SERVICE` | Yes | No (auto-granted) | Run the alarm playback service in the foreground so it is not killed by the OS. |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Yes (Android 14+) | No (auto-granted, requires Play Store declaration) | Declare the foreground service type as `specialUse` (alarm playback) to comply with Android 14+ restrictions. |
| `DISABLE_KEYGUARD` | Yes | No (auto-granted) | Allow the alarm activity to disable the keyguard and turn on the screen when an alarm fires. |

### Runtime Permission Flow (Android)

1. **App launch** — `POST_NOTIFICATIONS` is requested (Android 13+).
2. **App launch** — `SCHEDULE_EXACT_ALARM` availability is checked; user is redirected to system settings if not granted.
3. **App launch** — Battery optimization exemption is requested if not already granted.
4. **App launch** — `SYSTEM_ALERT_WINDOW` is checked; user is redirected to system settings if not granted.

---

## iOS Permissions

Configured at runtime via the `flutter_local_notifications` plugin. iOS permission usage descriptions should be added to [`ios/Runner/Info.plist`](ios/Runner/Info.plist) if additional entitlements are required in future.

| Permission | Required | Runtime Request | Purpose |
|---|---|---|---|
| **User Notifications** (`UNUserNotificationCenter`) | Yes | Yes (first launch) | Display local task reminders and alarm notifications. Covers alerts, sounds, and badges. |
| **Critical Alerts** (optional entitlement) | No (requires Apple entitlement) | Yes (if enabled) | Play alarm sounds even when the device is in Silent or Do Not Disturb mode. |
| **Background App Refresh** | Recommended | System setting | Allow the app to refresh notification scheduling state in the background. |

### Notification Options Requested on iOS

When the app requests notification permission it asks for:
- `alert` — display a visible notification banner.
- `sound` — play a notification/alarm sound.
- `badge` — update the app icon badge count.

### Info.plist Keys to Add (if additional permissions are needed)

If future features require additional permissions, add the corresponding usage description keys to `ios/Runner/Info.plist`:

```xml
<!-- Already handled by flutter_local_notifications at runtime -->
<!-- Add these keys only when the corresponding feature is introduced -->

<!-- If camera access is added -->
<key>NSCameraUsageDescription</key>
<string>Required for [feature].</string>

<!-- If photo library access is added -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Required for [feature].</string>
```

---

## Summary by Feature

| Feature | Android Permissions | iOS Permissions |
|---|---|---|
| Local notifications | `POST_NOTIFICATIONS`, `VIBRATE` | User Notifications (alert, sound, badge) |
| Exact / scheduled alarms | `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `WAKE_LOCK` | User Notifications (time-sensitive) |
| Alarm over lock screen | `USE_FULL_SCREEN_INTENT`, `SYSTEM_ALERT_WINDOW`, `DISABLE_KEYGUARD` | Critical Alerts entitlement (optional) |
| Background alarm delivery | `RECEIVE_BOOT_COMPLETED`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE` | Background App Refresh |

---

## Notes

- Permissions marked **auto-granted** are approved by the system and never shown to the user.
- Permissions marked **Settings redirect** open the appropriate system settings screen rather than displaying a standard dialog.
- All runtime permission requests include explanatory dialogs (rationale) before redirecting the user.
- The `FOREGROUND_SERVICE_SPECIAL_USE` permission requires a declaration in the Play Store listing under the "Sensitive app permissions" section.
