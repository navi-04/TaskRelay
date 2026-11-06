import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/task_provider.dart';
import '../providers/dashboard_provider.dart';
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

  @override
  void initState() {
    super.initState();
    // Note: alarm/overlay permissions are requested contextually when the
    // user actually sets an alarm (in the task form / TaskDetail save flow).
    // No startup prompt — that's annoying for users who don't use alarms.
  }

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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppTheme.getCardBorderColor(context),
              width: 1,
            ),
          ),
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
}
