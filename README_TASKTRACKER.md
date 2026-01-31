# Task Tracker - Production-Ready Flutter App

A production-ready, offline-first Flutter mobile application for daily task tracking with intelligent task carry-over logic, calendar-based navigation, weighted task limits, and notifications.

## 🎯 Features

### Core Functionality
- ✅ **Weighted Task System**: Each task has a weight, with daily limit enforcement
- ✅ **Intelligent Task Carry-Over**: Automatic carry-over of incomplete tasks to next day
- ✅ **Multi-Day Carry-Over**: Handles app closure for multiple days gracefully
- ✅ **Calendar View**: Monthly calendar with visual indicators for task completion
- ✅ **Streak Tracking**: Track consecutive days of task completion
- ✅ **Daily Notifications**: Customizable reminder notifications
- ✅ **Offline-First**: All data stored locally with Hive
- ✅ **Dark Mode**: Full dark mode support

### Screens
1. **Dashboard Screen**
   - Today's date and summary
   - Daily weight progress bar
   - Task completion statistics
   - Current streak display
   - Weekly analytics

2. **Calendar Screen**
   - Monthly calendar view
   - Color-coded days (completed, partial, missed)
   - Click dates to view tasks
   - Month summary statistics

3. **Daily Task Screen**
   - List of tasks for selected date
   - Add, edit, delete tasks
   - Toggle completion status
   - Visual carry-over indicators
   - Weight tracking

## 🏗️ Architecture

### Clean Architecture with MVVM

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart          # App-wide constants
│   └── utils/
│       └── date_utils.dart              # Date helper utilities
│
├── data/
│   ├── datasources/
│   │   ├── task_local_datasource.dart   # Task Hive operations
│   │   ├── settings_local_datasource.dart
│   │   └── day_summary_local_datasource.dart
│   ├── models/
│   │   ├── task_entity.dart             # Task data model
│   │   ├── settings_entity.dart         # Settings model
│   │   └── day_summary_entity.dart      # Day summary model
│   └── repositories/
│       ├── task_repository.dart         # Task business logic
│       ├── settings_repository.dart
│       └── day_summary_repository.dart
│
├── domain/
│   └── services/
│       ├── notification_service.dart     # Notification management
│       └── task_carry_over_service.dart  # CORE carry-over logic
│
└── presentation/
    ├── providers/
    │   ├── providers.dart                # Dependency injection
    │   ├── task_provider.dart            # Task state management
    │   ├── settings_provider.dart        # Settings state
    │   └── dashboard_provider.dart       # Dashboard computed state
    └── screens/
        └── dashboard/
            ├── dashboard_screen.dart     # Main dashboard UI
            ├── calendar_screen.dart      # Calendar view UI
            └── daily_task_screen.dart    # Task list UI
```

## 🧠 Core Business Logic: Task Carry-Over

### The Problem
When users don't complete tasks by end of day, those tasks should automatically carry over to the next day. This becomes complex when:
- App is closed for multiple days
- Multiple incomplete tasks from different dates
- Need to maintain carry-over history

### The Solution
Located in `task_carry_over_service.dart`:

```dart
// 1. Detects incomplete tasks before today
// 2. Processes day-by-day (not direct jump to today)
// 3. Updates task's currentDate while preserving originalDate
// 4. Marks task as isCarriedOver = true
// 5. Updates day summaries
// 6. Sends notifications
```

### Multi-Day Carry-Over Example
```
Day 1: User creates Task A (weight: 5)
Day 2: User closes app without completing Task A
       → Task A remains on Day 1 (incomplete)
Day 3: User opens app
       → Carry-over detects Task A is incomplete
       → Moves Task A from Day 1 to Day 2
       → Then moves Task A from Day 2 to Day 3
       → Task A now shows on Day 3 with "Carried Over" badge
```

## 📦 Tech Stack

- **Flutter**: Cross-platform mobile framework
- **Riverpod**: State management (v2.6+)
- **Hive**: Local database (offline-first)
- **flutter_local_notifications**: Push notifications
- **table_calendar**: Calendar widget
- **intl**: Date formatting
- **uuid**: Unique ID generation
- **equatable**: Value equality

## 🚀 Setup Instructions

### Prerequisites
- Flutter SDK 3.10.7 or higher
- Dart SDK 3.10.7 or higher

### Installation

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd sampleapp
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code** (Hive adapters)
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
   
   This generates:
   - `task_entity.g.dart`
   - `settings_entity.g.dart`
   - `day_summary_entity.g.dart`

4. **Run the app**
   ```bash
   flutter run
   ```

### For Development
Watch for file changes and auto-generate:
```bash
flutter pub run build_runner watch --delete-conflicting-outputs
```

## 📱 Platform-Specific Setup

### Android
- Minimum SDK: 21 (Android 5.0)
- Target SDK: 34
- Notifications work out of the box

### iOS
- Minimum iOS: 12.0
- Requires notification permission (handled automatically)

## 🧪 Testing

### Run Tests
```bash
flutter test
```

### Generate Coverage
```bash
flutter test --coverage
```

## 📊 Data Models

### TaskEntity
```dart
{
  id: String,              // UUID
  title: String,           // Task title
  description: String?,    // Optional description
  weight: int,             // Task weight (for daily limit)
  isCompleted: bool,       // Completion status
  createdDate: String,     // Date created (yyyy-MM-dd)
  originalDate: String,    // Original assigned date
  currentDate: String,     // Current date (changes on carry-over)
  isCarriedOver: bool,     // Carried over flag
  completedAt: DateTime?,  // Completion timestamp
}
```

### SettingsEntity
```dart
{
  dailyWeightLimit: int,        // Max points per day
  notificationsEnabled: bool,   // Notification toggle
  notificationHour: int,        // Reminder hour (0-23)
  notificationMinute: int,      // Reminder minute (0-59)
  isDarkMode: bool,             // Dark mode toggle
  showCarryOverAlerts: bool,    // Carry-over alert toggle
}
```

### DaySummaryEntity
```dart
{
  date: String,             // Date (yyyy-MM-dd)
  totalTasks: int,          // Total tasks for day
  completedTasks: int,      // Completed count
  totalWeight: int,         // Total weight
  completedWeight: int,     // Completed weight
  carriedOverTasks: int,    // Carried over count
  isFullyCompleted: bool,   // All tasks done?
  hasTasks: bool,           // Has any tasks?
  lastUpdated: DateTime,    // Last update time
}
```

## 🎨 UI/UX Features

### Color Coding
- **Green**: Fully completed days/tasks
- **Yellow/Amber**: Partially completed or carried over
- **Red**: Missed or over limit
- **Blue**: Active/selected items

### Animations
- Smooth progress bar animations
- Card transitions
- List item animations (300ms duration)

### Accessibility
- Semantic labels for screen readers
- High contrast colors
- Proper touch targets (48x48 minimum)

## 🔔 Notification System

### Daily Reminder
- Scheduled at user-defined time
- Shows pending task count and weight
- Alerts for carried-over tasks
- Persists across app restarts

### Carry-Over Alert
- Immediate notification when tasks carry over
- Shows number of tasks and total weight
- Can be disabled in settings

## 📈 Analytics & Insights

### Dashboard Metrics
- **Streak**: Consecutive days completed
- **Daily Weight**: Used vs. remaining capacity
- **Task Summary**: Total, completed, pending counts
- **Weekly Stats**:
  - Completion percentage
  - Missed tasks count
  - Average daily load

### Smart Suggestions
- Warns when carried tasks exceed daily limit
- Suggests task rescheduling
- Alerts for low remaining capacity

## 🔒 Data Persistence

- **Hive Boxes**:
  - `tasks_box`: All tasks
  - `settings_box`: User settings
  - `day_summary_box`: Cached day summaries

- **Location**: Platform-specific app data directory
- **Backup**: Can be backed up with app data (platform-dependent)

## 🛠️ Customization

### Change Daily Weight Limit
```dart
ref.read(settingsProvider.notifier).updateDailyWeightLimit(15);
```

### Change Notification Time
```dart
ref.read(settingsProvider.notifier).updateNotificationSettings(
  hour: 8,    // 8 AM
  minute: 30, // 8:30 AM
);
```

### Toggle Dark Mode
```dart
ref.read(settingsProvider.notifier).toggleDarkMode();
```

## 🐛 Troubleshooting

### Code Generation Issues
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Hive Initialization Errors
- Ensure `Hive.initFlutter()` runs before any Hive operations
- Check that adapters are registered
- Verify box names match constants

### Notification Not Working
- Check notification permissions
- Verify timezone data is initialized
- Ensure notification service is initialized in main()

## 📝 Future Enhancements

- [ ] Task categories/tags
- [ ] Cloud sync (Firebase/Supabase)
- [ ] Task templates
- [ ] Recurring tasks
- [ ] Task priority levels
- [ ] Export/import functionality
- [ ] Widget for home screen
- [ ] Task sharing
- [ ] Pomodoro timer integration
- [ ] Goal setting and tracking

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Author

Senior Mobile Architect & Flutter Expert

---

**Note**: Remember to run code generation after modifying any model with Hive or Riverpod annotations:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```
