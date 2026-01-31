import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'data/models/task_entity.dart';
import 'data/models/settings_entity.dart';
import 'data/models/day_summary_entity.dart';
import 'data/models/task_type.dart';
import 'data/models/task_priority.dart';
import 'data/models/custom_task_type.dart';
import 'presentation/providers/providers.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/task_provider.dart';
import 'presentation/providers/dashboard_provider.dart';
import 'presentation/providers/custom_types_provider.dart';
import 'presentation/screens/main_navigation_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive
  await Hive.initFlutter();
  
  // Register Hive Adapters
  Hive.registerAdapter(TaskEntityAdapter());
  Hive.registerAdapter(SettingsEntityAdapter());
  Hive.registerAdapter(DaySummaryEntityAdapter());
  Hive.registerAdapter(TaskTypeAdapter());
  Hive.registerAdapter(TaskPriorityAdapter());
  Hive.registerAdapter(CustomTaskTypeAdapter());
  Hive.registerAdapter(CustomPriorityAdapter());
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    try {
      // Initialize data sources
      await ref.read(taskLocalDataSourceProvider).init();
      await ref.read(settingsLocalDataSourceProvider).init();
      await ref.read(daySummaryLocalDataSourceProvider).init();
      
      // Initialize custom types
      await ref.read(customTypesProvider.notifier).init();
      
      // Reload settings after box is initialized
      ref.read(settingsProvider.notifier).reloadSettings();
      
      // Reload tasks after boxes are initialized
      ref.read(taskStateProvider.notifier).loadTasksForSelectedDate();
      
      // Initialize notification service
      await ref.read(notificationServiceProvider).initialize();
      await ref.read(notificationServiceProvider).requestPermissions();
      
      // Process any pending carry-overs (this will also refresh task state)
      final carryOverResult = await ref.read(taskStateProvider.notifier).processCarryOverAndRefresh();
      
      // Schedule daily reminder
      final carryOverService = ref.read(taskCarryOverServiceProvider);
      await carryOverService.scheduleDailyReminder();
      
      // Show carry-over notification if tasks were carried
      if (carryOverResult.hasCarriedTasks) {
        print('Carried over ${carryOverResult.carriedCount} tasks '
            'with total weight ${carryOverResult.totalWeight}');
      }
      
      // Invalidate providers to refresh UI with actual data
      ref.invalidate(dashboardProvider);
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('Initialization error: $e');
      setState(() {
        _isInitialized = true; // Allow app to start even if error
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final isDark = brightness == Brightness.dark;
      return MaterialApp(
        home: Scaffold(
          backgroundColor: isDark ? Colors.black : Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('TaskRelay',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Only watch settings after initialization is complete
    final settings = ref.watch(settingsProvider);
    final isDark = settings.isDarkMode;
    final isFirstLaunch = settings.isFirstLaunch;
    
    return MaterialApp(
      title: 'TaskRelay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: isFirstLaunch ? const OnboardingScreen() : const MainNavigationScreen(),
    );
  }
}
