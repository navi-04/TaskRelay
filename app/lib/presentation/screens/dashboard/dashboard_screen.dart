import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final settings = ref.watch(settingsProvider);
    final taskState = ref.watch(taskStateProvider);
    final streak = dashboard.streak;

    return Scaffold(
      appBar: _buildAppBar(context, settings.isDarkMode, ref),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Focus header — progress ring + date + status
            _buildFocusHeader(context, dashboard, taskState),
            const SizedBox(height: 10),

            // Quick stats row
            _buildQuickStatsRow(context, dashboard, taskState),
            const SizedBox(height: 10),

            // Progress card — expands to fill remaining space
            Expanded(
              flex: 5,
              child: _buildProgressCard(context, dashboard, taskState),
            ),
            const SizedBox(height: 10),

            // Weekly card — expands equally
            Expanded(
              flex: 5,
              child: _buildWeeklyCard(context, dashboard.weeklyStats),
            ),

            // Streak banner — only shows if there's a streak
            if (streak > 0) ...[
              const SizedBox(height: 10),
              _buildStreakBanner(context, streak),
            ],
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, bool isDarkMode, WidgetRef ref) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: const Icon(Icons.task_alt, color: AppTheme.primaryColor, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'TaskRelay',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () {
            ref.invalidate(dashboardProvider);
            ref.read(taskStateProvider.notifier).loadTasksForSelectedDate();
          },
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: Icon(
            isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 20,
          ),
          onPressed: () => ref.read(settingsProvider.notifier).toggleDarkMode(),
          tooltip: 'Toggle Theme',
        ),
      ],
    );
  }

  Widget _buildFocusHeader(
    BuildContext context,
    DashboardStats dashboard,
    TaskState taskState,
  ) {
    final isToday = taskState.selectedDate == dashboard.todayDate;
    final totalTasks = isToday
        ? taskState.tasks.length
        : (dashboard.todaySummary?.totalTasks ?? 0);
    final completedTasks = isToday
        ? taskState.completedTasks.length
        : (dashboard.todaySummary?.completedTasks ?? 0);
    final progress = totalTasks > 0 ? completedTasks / totalTasks : 0.0;

    final now = DateTime.now();
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${weekdayNames[now.weekday - 1]}, ${monthNames[now.month - 1]} ${now.day}';

    final hour = now.hour;
    final String greeting = hour < 12 ? 'Good morning'
        : hour < 17 ? 'Good afternoon'
        : 'Good evening';

    Color progressColor;
    String statusText;
    if (totalTasks == 0) {
      progressColor = AppTheme.getSecondaryTextColor(context);
      statusText = 'No tasks today';
    } else if (progress >= 1.0) {
      progressColor = AppTheme.success;
      statusText = 'All done!';
    } else if (dashboard.isOverLimit) {
      progressColor = AppTheme.error;
      statusText = 'Over limit';
    } else {
      progressColor = AppTheme.primaryColor;
      statusText = '$completedTasks of $totalTasks done';
    }

    return GradientCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: AppTheme.getProgressBackgroundColor(context),
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  greeting,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.getSecondaryTextColor(context),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: progressColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: progressColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsRow(
    BuildContext context,
    DashboardStats dashboard,
    TaskState taskState,
  ) {
    final isToday = taskState.selectedDate == dashboard.todayDate;
    final completed = isToday
        ? taskState.completedTasks.length
        : (dashboard.todaySummary?.completedTasks ?? 0);
    final total = isToday
        ? taskState.tasks.length
        : (dashboard.todaySummary?.totalTasks ?? 0);
    final pending = (total - completed).clamp(0, total);
    final carried = isToday
        ? taskState.carriedOverTasks.length
        : (dashboard.todaySummary?.carriedOverTasks ?? 0);

    return Row(
      children: [
        Expanded(child: _buildStatChip(context, '$completed', 'Done', AppTheme.success)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatChip(context, '$pending', 'Pending', AppTheme.warning)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatChip(context, '$carried', 'Carried', AppTheme.info)),
      ],
    );
  }

  Widget _buildStatChip(BuildContext context, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.getSecondaryTextColor(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    DashboardStats dashboard,
    TaskState taskState,
  ) {
    final isToday = taskState.selectedDate == dashboard.todayDate;
    final totalTasks = isToday
        ? taskState.tasks.length
        : (dashboard.todaySummary?.totalTasks ?? 0);
    final completedTasks = isToday
        ? taskState.completedTasks.length
        : (dashboard.todaySummary?.completedTasks ?? 0);
    final taskProgress = totalTasks > 0 ? completedTasks / totalTasks : 0.0;
    final isOverLimit = dashboard.isOverLimit;
    final limitColor = isOverLimit ? AppTheme.error : AppTheme.primaryColor;

    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Progress',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          _buildProgressRow(
            context,
            label: dashboard.progressLabel,
            trailing: '${dashboard.formattedUsedValue} / ${dashboard.formattedDailyLimitValue}',
            value: (dashboard.progressPercentage / 100).clamp(0.0, 1.0),
            color: limitColor,
          ),
          const Spacer(),
          _buildProgressRow(
            context,
            label: 'Tasks Completed',
            trailing: '$completedTasks / $totalTasks',
            value: taskProgress,
            color: AppTheme.success,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildProgressRow(
    BuildContext context, {
    required String label,
    required String trailing,
    required double value,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.getSecondaryTextColor(context),
              ),
            ),
            Text(
              trailing,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusXS),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 7,
            backgroundColor: AppTheme.getProgressBackgroundColor(context),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyCard(BuildContext context, Map<String, dynamic> stats) {
    final completionRate = stats['completionPercentage'] as double? ?? 0.0;
    final missed = stats['missedTasks'] ?? 0;
    final completed = stats['completedTasks'] ?? 0;
    final avgLoad = (stats['averageDailyLoad'] as double? ?? 0).toStringAsFixed(1);

    return GradientCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'This Week',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${completionRate.toStringAsFixed(0)}% done',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeeklyStat(context, '$completed', 'Completed', AppTheme.success),
                VerticalDivider(
                  color: AppTheme.getCardBorderColor(context),
                  width: 1,
                  thickness: 1,
                ),
                _buildWeeklyStat(context, '$missed', 'Missed', AppTheme.error),
                VerticalDivider(
                  color: AppTheme.getCardBorderColor(context),
                  width: 1,
                  thickness: 1,
                ),
                _buildWeeklyStat(context, avgLoad, 'Avg Load', AppTheme.info),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildWeeklyStat(
    BuildContext context,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.getSecondaryTextColor(context),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildStreakBanner(BuildContext context, int streak) {
    const orange = Color(0xFFFF6B35);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: orange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        border: Border.all(color: orange.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: orange, size: 18),
          const SizedBox(width: 8),
          Text(
            '$streak ${streak == 1 ? 'day' : 'days'} streak',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: orange,
            ),
          ),
          const Spacer(),
          if (streak >= 7)
            Text(
              'On Fire!',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: orange.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
