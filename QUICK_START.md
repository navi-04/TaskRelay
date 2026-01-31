# Task Tracker - Quick Start

## ✅ Setup Complete!

All dependencies have been installed and code has been generated successfully.

## 🚀 Run the App

### Option 1: Using VS Code
1. Open Command Palette (Ctrl+Shift+P / Cmd+Shift+P)
2. Type "Flutter: Select Device"
3. Choose your device (Android emulator, iOS simulator, or Chrome)
4. Press F5 or click "Run > Start Debugging"

### Option 2: Using Terminal
```bash
# See available devices
flutter devices

# Run on a specific device
flutter run -d <device_id>

# Or just run (Flutter will pick the first available device)
flutter run
```

## 📱 First Launch

When you first launch the app, it will:
1. ✅ Initialize Hive database
2. ✅ Create default settings (daily limit: 10 points)
3. ✅ Request notification permissions (iOS)
4. ✅ Check for pending task carry-overs
5. ✅ Schedule daily reminder notification
6. ✅ Show the Dashboard screen

## 🎯 Quick Feature Tour

### Dashboard Screen (Home)
- View today's date and streak
- See daily weight progress (used/remaining)
- Check task completion statistics
- View weekly analytics
- Click "View Today's Tasks" to see tasks
- Click calendar icon to view monthly calendar
- Click moon/sun icon to toggle dark mode

### Adding Your First Task
1. Click "View Today's Tasks" button
2. Click the floating "+" button
3. Fill in:
   - Title: e.g., "Complete project report"
   - Description: e.g., "Write executive summary" (optional)
   - Weight: e.g., "3" (affects daily limit)
4. Click "Add"

### Calendar View
- Click calendar icon in Dashboard app bar
- See color-coded days:
  - 🟢 Green = All tasks completed
  - 🟡 Yellow = Some tasks completed
  - 🔴 Red = No tasks completed
  - ⚪ Gray = No tasks scheduled
- Tap any date to view/edit tasks for that day

### Testing Carry-Over
1. Add a task for today
2. Don't complete it
3. Change your device date to tomorrow
4. Reopen the app
5. The task will automatically carry over with a "Carried Over" badge!

## ⚙️ Settings & Customization

### Change Daily Weight Limit
Currently hardcoded to 10 points. To change:
1. Edit `lib/core/constants/app_constants.dart`
2. Modify `defaultDailyWeightLimit`
3. Hot reload

### Change Notification Time
Currently set to 9:00 AM. To change:
1. Edit `lib/core/constants/app_constants.dart`
2. Modify `defaultNotificationHour` and `defaultNotificationMinute`
3. Hot reload

### Enable/Disable Notifications
Use the settings provider in code, or add a settings screen UI (future enhancement).

## 🎨 Theme Toggle
Click the moon/sun icon in the Dashboard app bar to switch between light and dark mode.

## 📊 Understanding Task Weights

**What is Weight?**
- Each task has a "weight" (difficulty/time estimate)
- Typical values: 1-5 points
- Daily limit helps prevent overcommitment

**Examples:**
- Small task (reply to email): 1 point
- Medium task (write document): 3 points
- Large task (complete presentation): 5 points

**Daily Limit (default 10 points):**
- You can add tasks totaling up to 10 points per day
- Exceeding limit shows a warning (red)
- Helps with realistic planning

## 🔔 Notifications

### Daily Reminder
- Sent at 9:00 AM (default)
- Shows pending task count and total weight
- Alerts if tasks are carried over

### Carry-Over Alert
- Sent when incomplete tasks are carried to today
- Shows count and total weight
- Helps you stay aware of pending work

### iOS Note
On first launch, iOS will ask for notification permission. Tap "Allow" to enable notifications.

### Android Note
Notifications work automatically. No permission needed.

## 🧪 Testing Scenarios

### Test 1: Basic Flow
1. ✅ Add a task
2. ✅ Complete it (check the checkbox)
3. ✅ See completion count update
4. ✅ View in calendar (should show green)

### Test 2: Carry-Over
1. ✅ Add task today
2. ✅ Leave it incomplete
3. ✅ Close app
4. ✅ Change device date to tomorrow
5. ✅ Reopen app
6. ✅ See task with "Carried Over" badge

### Test 3: Weight Limit
1. ✅ Add tasks totaling 12 points (exceeds 10 limit)
2. ✅ See red warning "Over limit by 2 points"
3. ✅ Progress bar shows over 100%

### Test 4: Streak
1. ✅ Complete all tasks today
2. ✅ Add and complete tasks tomorrow
3. ✅ See streak increase to 1 day
4. ✅ Continue for multiple days

### Test 5: Multi-Day Carry-Over
1. ✅ Add task on Day 1
2. ✅ Don't complete it
3. ✅ Change to Day 4 (skip 3 days)
4. ✅ Reopen app
5. ✅ Task should be on Day 4 with carry-over badge

## 🐛 Troubleshooting

### Issue: App won't start
**Solution:**
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

### Issue: White screen on launch
**Solution:** Wait a few seconds. The app initializes Hive and processes carry-overs.

### Issue: Notifications not showing
**Solution:** 
- iOS: Check Settings > Notifications > Task Tracker
- Android: Check notification settings in device settings
- Verify notification time is in the future

### Issue: Tasks not persisting
**Solution:** Check that Hive initialized successfully. Look for initialization errors in console.

### Issue: Carry-over not working
**Solution:** 
- Ensure tasks are not completed
- Verify device date change is recognized
- Check console for carry-over processing logs

## 📈 Performance Tips

### The app uses caching for performance:
- Day summaries are cached (no recalculation needed)
- Tasks are indexed by date
- Database operations are optimized

### If you have 1000+ tasks:
- App will still be fast
- Summaries prevent slow calculations
- Only loads tasks for selected date

## 🎓 Architecture Overview

```
Your Tap/Action
      ↓
  UI Screen (Presentation)
      ↓
  Provider/State Notifier
      ↓
  Repository (Business Logic)
      ↓
  Data Source (Hive)
      ↓
  Local Database
      ↓
  State Updates
      ↓
  UI Auto-Refreshes
```

## 📚 Learn More

- **Full Documentation**: See [README_TASKTRACKER.md](README_TASKTRACKER.md)
- **Setup Guide**: See [SETUP_GUIDE.md](SETUP_GUIDE.md)
- **Project Summary**: See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)

## 🚀 Ready to Go!

Everything is set up and ready. Just run:

```bash
flutter run
```

Enjoy your new Task Tracker app! 🎉

---

**Need Help?** Check the documentation files or create an issue.
