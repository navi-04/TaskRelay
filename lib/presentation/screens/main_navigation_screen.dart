import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../data/models/task_type.dart';
import '../../data/models/task_priority.dart';
import '../../core/theme/app_theme.dart';
import 'dashboard/dashboard_screen.dart';
import 'dashboard/daily_task_screen.dart';
import 'dashboard/calendar_screen.dart';
import 'statistics/statistics_screen.dart';
import 'profile/profile_screen.dart';

/// Main navigation shell with bottom navigation bar
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    DailyTaskScreen(),
    CalendarScreen(),
    StatisticsScreen(),
    ProfileScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Refresh data when switching to dashboard
    if (index == 0) {
      // Process carry-over and refresh dashboard
      ref.read(taskStateProvider.notifier).processCarryOverAndRefresh();
      ref.invalidate(dashboardProvider);
    }
    // Reset to today and refresh tasks when switching to tasks screen
    if (index == 1) {
      // Process carry-over first, then load today's tasks
      ref.read(taskStateProvider.notifier).processCarryOverAndRefresh().then((_) {
        ref.read(taskStateProvider.notifier).loadTasksForToday();
      });
    }
    // Refresh stats when switching to stats screen
    if (index == 3) {
      ref.read(taskStateProvider.notifier).loadTasksForToday();
      ref.invalidate(dashboardProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabTapped,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: const Duration(milliseconds: 300),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.task_outlined),
              selectedIcon: Icon(Icons.task),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: Icon(Icons.analytics_outlined),
              selectedIcon: Icon(Icons.analytics),
              label: 'Stats',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QuickAddTaskSheet(),
    );
  }
}

/// Complete task creation bottom sheet
class QuickAddTaskSheet extends ConsumerStatefulWidget {
  const QuickAddTaskSheet({super.key});

  @override
  ConsumerState<QuickAddTaskSheet> createState() => _QuickAddTaskSheetState();
}

class _QuickAddTaskSheetState extends ConsumerState<QuickAddTaskSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  int selectedHours = 0;
  int selectedMinutes = 30;
  TaskType selectedType = TaskType.task;
  TaskPriority selectedPriority = TaskPriority.medium;
  bool isPermanent = false;
  DateTime? alarmTime;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[600] 
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  'New Task',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Task title
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title *',
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                
                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                // Task Type and Priority row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TaskType>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: TaskType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.label, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedType = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<TaskPriority>(
                        value: selectedPriority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: TaskPriority.values.map((priority) {
                          return DropdownMenuItem(
                            value: priority,
                            child: Text(priority.label, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedPriority = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Duration (Hours and Minutes)
                Text(
                  'Duration *',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[300] 
                        : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Hours dropdown
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedHours,
                        decoration: const InputDecoration(
                          labelText: 'Hours',
                          prefixIcon: Icon(Icons.schedule),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: List.generate(25, (index) => index).map((hour) {
                          return DropdownMenuItem(
                            value: hour,
                            child: Text('$hour h', style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedHours = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Minutes dropdown
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectedMinutes,
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          prefixIcon: Icon(Icons.timer),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55].map((minute) {
                          return DropdownMenuItem(
                            value: minute,
                            child: Text('$minute m', style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedMinutes = value!;
                          });
                        },
                        validator: (value) {
                          if (selectedHours == 0 && (value == null || value == 0)) {
                            return 'Duration required';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Notes
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                
                // Permanent task toggle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.blue.withOpacity(0.1) 
                        : Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.blue.withOpacity(0.3) 
                          : Colors.blue.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.repeat,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Permanent Task',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shows up every day until deleted',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.grey[400] 
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isPermanent,
                        onChanged: (value) {
                          setState(() {
                            isPermanent = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Alarm time picker
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? const Color(0xFFFF6B35).withOpacity(0.1) 
                        : const Color(0xFFFF6B35).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? const Color(0xFFFF6B35).withOpacity(0.3) 
                          : const Color(0xFFFF6B35).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.alarm,
                        color: Color(0xFFFF6B35),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set Reminder',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              alarmTime != null
                                  ? 'Set for ${alarmTime!.hour.toString().padLeft(2, '0')}:${alarmTime!.minute.toString().padLeft(2, '0')}'
                                  : 'No reminder set',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).brightness == Brightness.dark 
                                    ? Colors.grey[400] 
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (alarmTime != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              alarmTime = null;
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.access_time, size: 20),
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: alarmTime != null
                                ? TimeOfDay(hour: alarmTime!.hour, minute: alarmTime!.minute)
                                : TimeOfDay.now(),
                          );
                          if (time != null) {
                            setState(() {
                              final now = DateTime.now();
                              alarmTime = DateTime(
                                now.year,
                                now.month,
                                now.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          }
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _submitTask,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Task'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitTask() {
    if (_formKey.currentState!.validate()) {
      final durationMinutes = (selectedHours * 60) + selectedMinutes;
      
      // Validate duration
      if (durationMinutes < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Duration must be at least 5 minutes'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      
      if (durationMinutes > 24 * 60) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Duration cannot exceed 24 hours'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      
      final settings = ref.read(settingsProvider);
      final notifier = ref.read(taskStateProvider.notifier);
      
      // Format time for display
      String formatTime(int mins) {
        final h = mins ~/ 60;
        final m = mins % 60;
        if (h > 0 && m > 0) return '\${h}h \${m}m';
        if (h > 0) return '\${h}h';
        return '\${m}m';
      }
      
      if (notifier.wouldExceedLimit(durationMinutes, settings.dailyTimeLimitMinutes)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Adding this task would exceed your daily limit of \${formatTime(settings.dailyTimeLimitMinutes)}',
            ),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      
      notifier.addTask(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        durationMinutes: durationMinutes,
        taskType: selectedType,
        priority: selectedPriority,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isPermanent: isPermanent,
        alarmTime: alarmTime,
      );
      
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task added!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}
