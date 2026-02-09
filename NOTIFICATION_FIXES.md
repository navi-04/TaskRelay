# TaskRelay - Notification & Alarm Fixes

## Issues Fixed

### 1. ✅ Notifications only showing when app is opened
### 2. ✅ Alarm using notification sound instead of ringtone

---

## Changes Made

### Android Permissions (AndroidManifest.xml)
Added the following permissions to ensure notifications work even when the app is closed:
- `WAKE_LOCK` - Allows the app to wake up the device
- `USE_FULL_SCREEN_INTENT` - Enables full-screen alarm notifications
- `SYSTEM_ALERT_WINDOW` - Allows notifications to show over other apps

### Notification Receivers (AndroidManifest.xml)
Enhanced the notification receivers to:
- Set `android:enabled="true"` to ensure they're active
- Set `android:exported="true"` for the boot receiver (Android requirement)
- Added additional boot actions for various device manufacturers

### Notification Service (notification_service.dart)
- Updated notification channel ID to `task_alarms_v3` with proper alarm configuration
- Added `RawResourceAndroidNotificationSound` to use custom alarm ringtone
- Maintained all critical flags for alarm functionality:
  - `fullScreenIntent: true` - Shows full-screen notification
  - `category: AndroidNotificationCategory.alarm` - Marks as alarm
  - `visibility: NotificationVisibility.public` - Shows on lock screen
  - `ongoing: true` - Keeps notification visible
  - `additionalFlags: [4, 128]` - FLAG_INSISTENT | FLAG_SHOW_WHEN_LOCKED

---

## 🔴 ACTION REQUIRED: Add Alarm Sound

To enable the alarm ringtone (instead of notification sound), you need to add a sound file:

### Quick Setup (Choose One):

#### Option 1: Run the provided script
```batch
download_alarm_sound.bat
```

#### Option 2: Manual Setup
1. Download a free alarm sound from:
   - https://pixabay.com/sound-effects/search/alarm/
   - https://freesound.org/
   - https://www.soundjay.com/

2. Save it as `alarm_sound.mp3` or `alarm_sound.ogg`

3. Place it in: `android/app/src/main/res/raw/alarm_sound.mp3`

#### Option 3: PowerShell Command
```powershell
Invoke-WebRequest -Uri 'https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3' -OutFile 'android/app/src/main/res/raw/alarm_sound.mp3'
```

### After Adding the Sound:
```bash
flutter clean
flutter build apk
# or
flutter run
```

---

## Alternative: Use Default Sound (Temporary Fix)

If you don't want to add a custom sound right now, you can use the default notification sound:

**Edit:** `lib/domain/services/notification_service.dart`

**Line 76** - Comment out or remove the `sound:` parameter:

```dart
// Before:
sound: const RawResourceAndroidNotificationSound('alarm_sound'),

// After:
// sound: const RawResourceAndroidNotificationSound('alarm_sound'),
```

Do the same on **Line 398**.

Then rebuild:
```bash
flutter clean
flutter run
```

---

## Testing the Fixes

### Test 1: Background Notifications
1. Schedule an alarm for 1 minute from now
2. Close the app completely (swipe away from recent apps)
3. Wait for the scheduled time
4. ✅ Notification should appear even when app is closed

### Test 2: Lock Screen
1. Schedule an alarm
2. Lock your device
3. Wait for the alarm
4. ✅ Notification should show on lock screen and wake the device

### Test 3: Alarm Sound
1. Add the alarm sound file (see above)
2. Rebuild the app
3. Schedule an alarm
4. ✅ Should play your custom alarm sound (not default notification sound)

---

## Troubleshooting

### Notifications still not showing when app is closed?

1. **Check Android Battery Optimization:**
   - Settings → Apps → TaskRelay → Battery → Unrestricted

2. **Check Notification Permissions:**
   - Settings → Apps → TaskRelay → Notifications → Allow all

3. **Enable Alarm Permissions:**
   - Settings → Apps → TaskRelay → Alarms & reminders → Allow

4. **Disable Battery Saver mode** while testing

### Still using notification sound instead of alarm?

1. **Verify the sound file exists:**
   - Path: `android/app/src/main/res/raw/alarm_sound.mp3`
   - Must be exactly named: `alarm_sound.mp3` or `alarm_sound.ogg`

2. **Clear app data and reinstall:**
   ```bash
   flutter clean
   flutter run --release
   ```

3. **Check notification channel settings:**
   - On Android, once a notification channel is created, its sound cannot be changed
   - You may need to:
     - Uninstall the app completely
     - Reinstall with the new sound file

---

## Technical Details

### Why notifications weren't showing when app closed:
- Missing `WAKE_LOCK` permission prevented waking the device
- Boot receiver wasn't properly exported for Android 12+
- Missing flags for full-screen intent

### Why notification sound was used instead of alarm:
- No custom sound file configured
- Notification channel was using default sound settings
- `RawResourceAndroidNotificationSound` wasn't specified

### How it works now:
1. App schedules alarm using `AndroidScheduleMode.exactAllowWhileIdle`
2. Android AlarmManager triggers at exact time, even when app is closed
3. ScheduledNotificationReceiver receives the trigger
4. Notification shows with custom alarm sound
5. Device wakes up and shows full-screen notification on lock screen

---

## Files Modified

1. ✅ `android/app/src/main/AndroidManifest.xml` - Added permissions and improved receivers
2. ✅ `lib/domain/services/notification_service.dart` - Updated notification channels and alarm configuration
3. 📄 `download_alarm_sound.bat` - Helper script to download alarm sound
4. 📄 `android/app/src/main/res/raw/README_ALARM_SOUND.md` - Instructions for alarm sound

---

## Next Steps

1. **Add the alarm sound file** (see ACTION REQUIRED section above)
2. **Rebuild the app** with `flutter clean && flutter run`
3. **Test the notifications** (see Testing section above)
4. **Adjust battery settings** on your device if needed

---

## Questions?

See the comments in:
- `lib/domain/services/notification_service.dart` - Lines 65-77 and 388-400
- `android/app/src/main/res/raw/README_ALARM_SOUND.md`

The notification system is now configured for:
- ✅ Background operation (app closed)
- ✅ Full-screen alarms
- ✅ Lock screen notifications
- ✅ Custom alarm ringtone support
- ✅ Device wake-up
- ✅ Persistent until dismissed
