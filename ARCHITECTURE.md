# Task Tracker - Architecture Diagram

## 📐 Clean Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                          │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │  Dashboard   │  │   Calendar   │  │  Daily Task  │        │
│  │    Screen    │  │    Screen    │  │    Screen    │        │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘        │
│         │                  │                  │                 │
│         └──────────────────┴──────────────────┘                 │
│                            │                                     │
│                    ┌───────▼────────┐                          │
│                    │   Providers    │                          │
│                    │  (Riverpod)    │                          │
│                    └───────┬────────┘                          │
│                            │                                     │
└────────────────────────────┼─────────────────────────────────────┘
                             │
┌────────────────────────────┼─────────────────────────────────────┐
│                     DOMAIN LAYER                                 │
│                            │                                     │
│               ┌────────────┴───────────┐                        │
│               │                        │                        │
│      ┌────────▼────────┐    ┌─────────▼──────────┐           │
│      │  TaskCarryOver  │    │   Notification     │           │
│      │    Service      │    │     Service        │           │
│      └────────┬────────┘    └─────────┬──────────┘           │
│               │                        │                        │
└───────────────┼────────────────────────┼──────────────────────────┘
                │                        │
┌───────────────┼────────────────────────┼──────────────────────────┐
│                     DATA LAYER                                   │
│               │                        │                        │
│      ┌────────▼─────────────────┐     │                        │
│      │     Repositories         │     │                        │
│      │  ┌─────────────────┐   │     │                        │
│      │  │  Task Repo      │   │     │                        │
│      │  │  Settings Repo  │   │     │                        │
│      │  │  Summary Repo   │   │     │                        │
│      │  └────────┬────────┘   │     │                        │
│      └───────────┼────────────┘     │                        │
│                  │                    │                        │
│         ┌────────▼─────────────┐     │                        │
│         │   Data Sources       │     │                        │
│         │  ┌─────────────────┐ │     │                        │
│         │  │ Task DataSource │ │     │                        │
│         │  │Settings DataSrc │ │     │                        │
│         │  │Summary DataSrc  │ │     │                        │
│         │  └────────┬────────┘ │     │                        │
│         └───────────┼──────────┘     │                        │
│                     │                  │                        │
│            ┌────────▼──────────────────▼─────┐                │
│            │          Hive Database          │                │
│            │     (Local Persistence)         │                │
│            └─────────────────────────────────┘                │
│                                                                │
└──────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow Example: Adding a Task

```
1. USER TAPS "ADD TASK"
   │
   ├─> DailyTaskScreen._showAddTaskDialog()
   │
2. USER ENTERS DETAILS & CONFIRMS
   │
   ├─> taskStateProvider.notifier.addTask(...)
   │   │
   │   ├─> TaskStateNotifier receives call
   │   │
3. STATE NOTIFIER PROCESSES
   │
   ├─> taskRepository.addTask(task)
   │   │
   │   ├─> TaskRepository validates & processes
   │   │
4. REPOSITORY SAVES DATA
   │
   ├─> taskLocalDataSource.addTask(task)
   │   │
   │   ├─> Writes to Hive box
   │   │
5. DATA PERSISTED
   │
   ├─> Hive stores task locally
   │
6. UPDATE SUMMARY
   │
   ├─> summaryRepository.calculateAndSaveSummary(...)
   │
7. STATE UPDATES
   │
   ├─> StateNotifier calls loadTasksForSelectedDate()
   │
8. UI REFRESHES AUTOMATICALLY
   │
   └─> Screen rebuilds with new task
```

## 🔁 Task Carry-Over Flow

```
APP STARTUP
    │
    ├─> main() initializes Hive
    │
    ├─> Registers adapters
    │
    ├─> MyApp._initializeApp()
    │   │
    │   ├─> Initialize data sources
    │   ├─> Initialize notification service
    │   │
    │   └─> carryOverService.processCarryOver()
    │       │
    │       ├─> Get incomplete tasks before today
    │       │
    │       ├─> Calculate days difference
    │       │
    │       ├─> IF single day:
    │       │   └─> Carry to today directly
    │       │
    │       └─> IF multiple days:
    │           │
    │           ├─> Day-by-day carry-over loop
    │           │   │
    │           │   ├─> Day 1 → Day 2
    │           │   ├─> Day 2 → Day 3
    │           │   └─> ... → Today
    │           │
    │           ├─> Update currentDate
    │           ├─> Set isCarriedOver = true
    │           │
    │           ├─> Update day summaries
    │           │
    │           └─> Send notification
    │
    └─> Show Dashboard
```

## 📊 State Management Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    PROVIDERS                            │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  taskStateProvider                           │    │
│  │  - Current tasks list                        │    │
│  │  - Selected date                             │    │
│  │  - Loading state                             │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  settingsProvider                            │    │
│  │  - Daily weight limit                        │    │
│  │  - Notification settings                     │    │
│  │  - Theme preferences                         │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  dashboardProvider                           │    │
│  │  - Computed stats (streak, progress, etc)   │    │
│  │  - Reads from multiple providers             │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
          │                    │                  │
          │                    │                  │
          ▼                    ▼                  ▼
┌───────────────┐   ┌──────────────────┐   ┌──────────┐
│   Dashboard   │   │    Calendar      │   │  Tasks   │
│    Screen     │   │     Screen       │   │  Screen  │
└───────────────┘   └──────────────────┘   └──────────┘
```

## 💾 Database Schema (Hive)

```
┌─────────────────────────────────────────────────────────┐
│                    HIVE BOXES                           │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  tasks_box                                   │    │
│  │  Key: task.id (String)                       │    │
│  │  Value: TaskEntity                           │    │
│  │                                              │    │
│  │  Fields:                                     │    │
│  │  - id (String)                               │    │
│  │  - title (String)                            │    │
│  │  - description (String?)                     │    │
│  │  - weight (int)                              │    │
│  │  - isCompleted (bool)                        │    │
│  │  - createdDate (String)                      │    │
│  │  - originalDate (String)                     │    │
│  │  - currentDate (String)  ← Changes on carry │    │
│  │  - isCarriedOver (bool)                      │    │
│  │  - completedAt (DateTime?)                   │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  settings_box                                │    │
│  │  Key: 'user_settings' (String)               │    │
│  │  Value: SettingsEntity                       │    │
│  │                                              │    │
│  │  Fields:                                     │    │
│  │  - dailyWeightLimit (int)                    │    │
│  │  - notificationsEnabled (bool)               │    │
│  │  - notificationHour (int)                    │    │
│  │  - notificationMinute (int)                  │    │
│  │  - isDarkMode (bool)                         │    │
│  │  - showCarryOverAlerts (bool)                │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
│  ┌──────────────────────────────────────────────┐    │
│  │  day_summary_box                             │    │
│  │  Key: date (String "yyyy-MM-dd")             │    │
│  │  Value: DaySummaryEntity                     │    │
│  │                                              │    │
│  │  Fields:                                     │    │
│  │  - date (String)                             │    │
│  │  - totalTasks (int)                          │    │
│  │  - completedTasks (int)                      │    │
│  │  - totalWeight (int)                         │    │
│  │  - completedWeight (int)                     │    │
│  │  - carriedOverTasks (int)                    │    │
│  │  - isFullyCompleted (bool)                   │    │
│  │  - hasTasks (bool)                           │    │
│  │  - lastUpdated (DateTime)                    │    │
│  └──────────────────────────────────────────────┘    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## 🎨 UI Component Hierarchy

```
MaterialApp
  │
  └─> DashboardScreen (Home)
       │
       ├─> AppBar
       │   ├─> Calendar button
       │   └─> Theme toggle button
       │
       ├─> Body (ScrollView)
       │   ├─> Date Header
       │   ├─> Streak Card
       │   ├─> Weight Progress Card
       │   ├─> Task Summary Card
       │   ├─> Weekly Stats Card
       │   └─> "View Tasks" Button
       │
       └─> Navigation to:
           │
           ├─> CalendarScreen
           │   ├─> Legend
           │   ├─> TableCalendar
           │   │   └─> Custom day builder
           │   │       (colored by completion)
           │   └─> Month Summary
           │       └─> Navigate to →
           │
           └─> DailyTaskScreen
               ├─> Task Summary Header
               ├─> Task List
               │   └─> Task Cards
               │       ├─> Checkbox
               │       ├─> Title/Description
               │       ├─> Weight badge
               │       ├─> Carry-over badge
               │       ├─> Edit button
               │       └─> Delete button
               │
               └─> FAB (Add Task)
                   └─> Add Task Dialog
                       ├─> Title field
                       ├─> Description field
                       ├─> Weight field
                       └─> Add button
```

## 📅 Date Handling Strategy

```
Task Creation:
  createdDate = "2026-01-29"     (Never changes)
  originalDate = "2026-01-29"    (Never changes)
  currentDate = "2026-01-29"     (Changes on carry-over)

After 1 Day Carry-Over (Jan 30):
  createdDate = "2026-01-29"     (Unchanged)
  originalDate = "2026-01-29"    (Unchanged)
  currentDate = "2026-01-30"     (Updated)
  isCarriedOver = true           (Set)

After Another Carry-Over (Jan 31):
  createdDate = "2026-01-29"     (Unchanged)
  originalDate = "2026-01-29"    (Unchanged)
  currentDate = "2026-01-31"     (Updated again)
  isCarriedOver = true           (Still set)

This preserves:
  - When task was created
  - What day it was originally for
  - What day it's currently on
  - That it has been carried over
```

## 🔔 Notification Timeline

```
9:00 AM Daily Reminder:
  │
  ├─> Checks pending tasks
  ├─> Calculates total weight
  ├─> Counts carried-over tasks
  │
  └─> Sends notification:
      "You have 5 tasks (12 points) pending today.
       ⚠️ 2 tasks carried over from previous days!"

On Carry-Over Detection:
  │
  ├─> Immediate notification
  │
  └─> "⚠️ Tasks Carried Over
       3 incomplete tasks (8 points) carried to today."
```

## 📊 Performance Optimizations

```
1. Day Summary Caching
   ├─> Pre-calculated statistics
   ├─> No real-time aggregation needed
   └─> Fast calendar rendering

2. Indexed by Date
   ├─> Tasks stored by currentDate
   ├─> O(1) lookup for date
   └─> No full table scan

3. Lazy Loading
   ├─> Only load tasks for selected date
   ├─> Calendar loads summaries only
   └─> Minimal memory footprint

4. Batch Operations
   ├─> Bulk update for carry-over
   ├─> Single write transaction
   └─> Reduced I/O operations
```

---

**Architecture designed for:**
- ✅ Scalability
- ✅ Maintainability
- ✅ Testability
- ✅ Performance
- ✅ User Experience
