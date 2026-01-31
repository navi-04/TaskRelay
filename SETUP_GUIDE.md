## 🚀 Quick Start Guide

### Step 1: Install Dependencies
```bash
flutter pub get
```

### Step 2: Generate Required Code
The app uses Hive for database and requires code generation for type adapters.

**Run this command:**
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**What this does:**
- Generates `task_entity.g.dart` - Hive adapter for TaskEntity
- Generates `settings_entity.g.dart` - Hive adapter for SettingsEntity  
- Generates `day_summary_entity.g.dart` - Hive adapter for DaySummaryEntity

**Expected output:**
```
[INFO] Generating build script...
[INFO] Generating build script completed, took 342ms
[INFO] Creating build script snapshot......
[INFO] Creating build script snapshot... completed, took 8.4s
[INFO] Building new asset graph...
[INFO] Building new asset graph completed, took 1.2s
[INFO] Checking for unexpected pre-existing outputs....
[INFO] Checking for unexpected pre-existing outputs. completed, took 1ms
[INFO] Running build...
[INFO] Generating outputs
```

### Step 3: Verify Generated Files
Check that these files exist:
- `lib/data/models/task_entity.g.dart` ✅
- `lib/data/models/settings_entity.g.dart` ✅
- `lib/data/models/day_summary_entity.g.dart` ✅

### Step 4: Run the App
```bash
flutter run
```

## 🔄 During Development

If you modify any model files (task_entity.dart, settings_entity.dart, day_summary_entity.dart), you need to regenerate the adapters.

**For one-time generation:**
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**For continuous watching (recommended during development):**
```bash
flutter pub run build_runner watch --delete-conflicting-outputs
```

This will automatically regenerate files whenever you save changes.

## ⚠️ Common Issues

### Issue: "No built-in type adapter for TaskEntity"
**Solution:** You forgot to run code generation. Run:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Issue: "Conflicting outputs"
**Solution:** Use the `--delete-conflicting-outputs` flag:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Issue: Build runner fails
**Solution:** Clean and rebuild:
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Issue: Hive box not initialized
**Solution:** Ensure main.dart properly initializes everything:
1. `Hive.initFlutter()` is called
2. All adapters are registered
3. Data sources call `.init()` before use

## 📱 First Launch

On first launch, the app will:
1. Initialize Hive database
2. Create default settings (daily limit: 10 points)
3. Request notification permissions (iOS)
4. Check for any pending carry-over tasks
5. Schedule daily reminder notification

## 🎯 Testing the Carry-Over Logic

### Manual Test
1. Add a task for today
2. Don't complete it
3. Change your device date to tomorrow
4. Reopen the app
5. You should see the task carried over with a "Carried Over" badge

### Multi-Day Test
1. Add a task
2. Change date to 3 days in the future
3. Reopen app
4. The task should be on today's date with carry-over indicator

## 📊 App Flow

```
App Startup
    ↓
Initialize Hive
    ↓
Register Adapters
    ↓
Initialize Data Sources
    ↓
Initialize Notification Service
    ↓
Process Carry-Over (CRITICAL)
    ├── Find incomplete tasks before today
    ├── Carry over day-by-day
    ├── Update summaries
    └── Send notification if tasks carried
    ↓
Schedule Daily Reminder
    ↓
Show Dashboard
```

## 🎨 Customizing the App

### Change Default Daily Limit
Edit `lib/core/constants/app_constants.dart`:
```dart
static const int defaultDailyWeightLimit = 10; // Change this
```

### Change Default Notification Time
Edit `lib/core/constants/app_constants.dart`:
```dart
static const int defaultNotificationHour = 9;   // Change this
static const int defaultNotificationMinute = 0;  // Change this
```

### Modify Colors
Calendar colors are in `lib/core/constants/app_constants.dart`:
```dart
static const String completedColor = '#4CAF50';  // Green
static const String partialColor = '#FFC107';    // Amber
static const String missedColor = '#F44336';     // Red
```

## 📈 Understanding the Architecture

### Data Flow
```
UI Screen
    ↓
Provider/Notifier (State Management)
    ↓
Repository (Business Logic)
    ↓
Data Source (Hive Operations)
    ↓
Hive Database (Local Storage)
```

### Example: Adding a Task
```dart
// 1. User taps "Add Task" in UI
DailyTaskScreen._showAddTaskDialog()

// 2. Provider handles the action
taskStateProvider.notifier.addTask(...)

// 3. Repository creates the task entity
taskRepository.addTask(task)

// 4. Data source saves to Hive
taskLocalDataSource.addTask(task)
```

## 🔔 Notification Setup

### Android
Works out of the box. Notifications appear in system tray.

### iOS
1. App will request permission on first launch
2. User must grant permission
3. Notifications will appear in notification center

### Testing Notifications Locally
Change notification time to 1 minute in the future:
```dart
final now = DateTime.now();
ref.read(settingsProvider.notifier).updateNotificationSettings(
  hour: now.hour,
  minute: now.minute + 1,
);
```

## 🧪 Testing Checklist

- [ ] Add task ✅
- [ ] Complete task ✅
- [ ] Edit task ✅
- [ ] Delete task ✅
- [ ] Task carries over when incomplete ✅
- [ ] Multi-day carry-over works ✅
- [ ] Calendar shows correct colors ✅
- [ ] Streak calculates correctly ✅
- [ ] Daily weight limit enforced ✅
- [ ] Notifications appear ✅
- [ ] Dark mode toggles ✅
- [ ] App persists data after restart ✅

## 🎓 Learning Resources

### Clean Architecture
- Presentation Layer: UI components
- Domain Layer: Business logic & services
- Data Layer: Data sources & repositories

### Riverpod
- Providers: Dependency injection
- StateNotifiers: Mutable state
- ConsumerWidgets: UI that watches state

### Hive
- Boxes: Like tables
- Type Adapters: Serialization
- Lazy boxes: Memory efficient for large data

## 📞 Support

If you encounter issues:
1. Check this setup guide
2. Review the main README
3. Check the code comments
4. Create an issue with:
   - Error message
   - Steps to reproduce
   - Device/OS info
   - Flutter version (`flutter --version`)

---

**Ready to start?**
```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

Happy coding! 🚀
