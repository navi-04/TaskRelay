import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Dashboard Screen - Main screen showing today's overview with modern UI
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final settings = ref.watch(settingsProvider);
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.read(taskStateProvider.notifier).loadTasksForSelectedDate();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // App Bar
            _buildSliverAppBar(context, dashboard.todayDate, settings.isDarkMode, ref),
            
            // Content
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Greeting Section
                  _buildGreetingSection(context),
                  const SizedBox(height: 24),
                  
                  // Streak Card with Gradient
                  _buildStreakCard(context, dashboard.streak),
                  const SizedBox(height: 16),
                  
                  // Progress Overview
                  _buildProgressOverview(
                    context,
                    dashboard.usedMinutes,
                    dashboard.dailyLimitMinutes,
                    dashboard.remainingMinutes,
                    dashboard.progressPercentage,
                    dashboard.isOverLimit,
                    dashboard.todaySummary,
                    dashboard,
                  ),
                  const SizedBox(height: 16),
                  
                  // Quick Stats Row
                  _buildQuickStatsRow(context, dashboard),
                  const SizedBox(height: 24),
                  
                  // Today's Progress
                  _buildTodaysProgress(context, dashboard.todaySummary),
                  const SizedBox(height: 24),
                  
                  // Weekly Overview
                  _buildWeeklyOverview(context, dashboard.weeklyStats),
                  const SizedBox(height: 24),
                  
                  // Motivational Quote
                  _buildMotivationalCard(context, dashboard.streak),
                  const SizedBox(height: 100), // Bottom padding for nav bar
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSliverAppBar(BuildContext context, String date, bool isDarkMode, WidgetRef ref) {
    return SliverAppBar(
      floating: true,
      pinned: false,
      expandedHeight: 60,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.task_alt, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'TaskRelay',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => ref.read(settingsProvider.notifier).toggleDarkMode(),
          tooltip: 'Toggle Theme',
        ),
      ],
    );
  }
  
  Widget _buildGreetingSection(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    IconData icon;
    
    if (hour < 12) {
      greeting = 'Good Morning! ☀️';
      icon = Icons.wb_sunny;
    } else if (hour < 17) {
      greeting = 'Good Afternoon! 🌤️';
      icon = Icons.wb_cloudy;
    } else {
      greeting = 'Good Evening! 🌙';
      icon = Icons.nights_stay;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Let\'s make today productive!',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[400] 
                : Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  Widget _buildStreakCard(BuildContext context, int streak) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF6B35), // Vibrant orange
            Color(0xFFF7931E), // Bright orange
            Color(0xFFFFB627), // Yellow-orange
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_fire_department,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.whatshot,
                      size: 18,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Current Streak',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$streak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        streak == 1 ? 'day' : 'days',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (streak >= 7)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🔥',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'On Fire!',
                    style: TextStyle(
                      color: Color(0xFFFF6B35),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildProgressOverview(
    BuildContext context,
    int usedMinutes,
    int limitMinutes,
    int remainingMinutes,
    double percentage,
    bool isOverLimit,
    dynamic summary,
    DashboardStats dashboard,
  ) {
    final totalTasks = summary?.totalTasks ?? 0;
    final completedTasks = summary?.completedTasks ?? 0;
    final taskProgress = totalTasks > 0 ? completedTasks / totalTasks : 0.0;
    
    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Today\'s Progress',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOverLimit 
                      ? AppTheme.error.withOpacity(0.1)
                      : AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOverLimit ? 'Over Limit' : 'On Track',
                  style: TextStyle(
                    color: isOverLimit ? AppTheme.error : AppTheme.success,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Time Progress
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Time Used'),
                        Text(
                          '${dashboard.formattedUsedTime} / ${dashboard.formattedDailyLimit}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isOverLimit ? AppTheme.error : AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (percentage / 100).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[700] 
                            : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isOverLimit ? AppTheme.error : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Task Progress
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tasks Completed'),
                        Text(
                          '$completedTasks / $totalTasks',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: taskProgress,
                        minHeight: 10,
                        backgroundColor: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[700] 
                            : Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickStatsRow(BuildContext context, dynamic dashboard) {
    return Row(
      children: [
        Expanded(
          child: _buildQuickStatCard(
            context,
            Icons.check_circle,
            'Completed',
            '${dashboard.todaySummary?.completedTasks ?? 0}',
            AppTheme.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            context,
            Icons.pending_actions,
            'Pending',
            '${(dashboard.todaySummary?.totalTasks ?? 0) - (dashboard.todaySummary?.completedTasks ?? 0)}',
            AppTheme.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            context,
            Icons.arrow_forward,
            'Carried',
            '${dashboard.todaySummary?.carriedOverTasks ?? 0}',
            Colors.amber,
          ),
        ),
      ],
    );
  }
  
  Widget _buildQuickStatCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[400] 
                  : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTodaysProgress(BuildContext context, dynamic summary) {
    final total = summary?.totalTasks ?? 0;
    final completed = summary?.completedTasks ?? 0;
    
    if (total == 0) {
      return GradientCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_task,
                size: 48,
                color: AppTheme.primaryColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks for today',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add tasks from the Tasks tab to get started!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[400] 
                    : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Task Completion',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(completed / total * 100).toInt()}%',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Circular progress visualization
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: completed / total,
                      strokeWidth: 12,
                      backgroundColor: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[700] 
                          : Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$completed',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'of $total',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[400] 
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWeeklyOverview(BuildContext context, Map<String, dynamic> stats) {
    final completionRate = stats['completionPercentage'] as double? ?? 0.0;
    
    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.analytics, color: AppTheme.info),
              ),
              const SizedBox(width: 12),
              Text(
                'Weekly Overview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeeklyStat(
                context,
                '${completionRate.toStringAsFixed(0)}%',
                'Completion',
                Icons.pie_chart,
                AppTheme.success,
              ),
              _buildWeeklyStat(
                context,
                '${stats['missedTasks'] ?? 0}',
                'Missed',
                Icons.cancel,
                AppTheme.error,
              ),
              _buildWeeklyStat(
                context,
                '${(stats['averageDailyLoad'] as double? ?? 0).toStringAsFixed(1)}',
                'Avg Load',
                Icons.fitness_center,
                AppTheme.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildWeeklyStat(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[400] 
                : Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  Widget _buildMotivationalCard(BuildContext context, int streak) {
    final quotes = [
      {'quote': 'The secret of getting ahead is getting started.', 'author': 'Mark Twain'},
      {'quote': 'It\'s not about being the best. It\'s about being better than you were yesterday.', 'author': 'Unknown'},
      {'quote': 'Small daily improvements are the key to staggering long-term results.', 'author': 'Unknown'},
      {'quote': 'Success is the sum of small efforts repeated day in and day out.', 'author': 'Robert Collier'},
      {'quote': 'The only way to do great work is to love what you do.', 'author': 'Steve Jobs'},
    ];
    
    final quoteIndex = streak % quotes.length;
    final selectedQuote = quotes[quoteIndex];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.1),
            AppTheme.primaryLight.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.format_quote, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                'Daily Motivation',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '"${selectedQuote['quote']}"',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '— ${selectedQuote['author']}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[400] 
                  : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
