import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Statistics Screen - Analytics and insights
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final taskState = ref.watch(taskStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
        },
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Productivity Score
              _buildSectionHeader(context, 'Productivity Score', Icons.speed),
              const SizedBox(height: 12),
              _buildProductivityScore(context, dashboard),
              const SizedBox(height: 24),

              // Weekly Performance
              _buildSectionHeader(context, 'Weekly Performance', Icons.trending_up),
              const SizedBox(height: 12),
              _buildWeeklyChart(context, ref, dashboard.weeklyStats),
              const SizedBox(height: 24),

              // Task Distribution
              _buildSectionHeader(context, 'Task Distribution', Icons.pie_chart),
              const SizedBox(height: 12),
              _buildTaskDistribution(context, taskState),
              const SizedBox(height: 24),

              // Achievements
              _buildSectionHeader(context, 'Achievements', Icons.emoji_events),
              const SizedBox(height: 12),
              _buildAchievements(context, dashboard),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildProductivityScore(BuildContext context, dynamic dashboard) {
    final completionRate = dashboard.weeklyStats['completionPercentage'] as double? ?? 0.0;
    final streakBonus = (dashboard.streak * 2).clamp(0, 20);
    final totalScore = ((completionRate * 0.8) + streakBonus).clamp(0.0, 100.0);

    Color scoreColor;
    String scoreLabel;
    if (totalScore >= 80) {
      scoreColor = AppTheme.success;
      scoreLabel = 'Excellent!';
    } else if (totalScore >= 60) {
      scoreColor = Colors.blue;
      scoreLabel = 'Good';
    } else if (totalScore >= 40) {
      scoreColor = AppTheme.warning;
      scoreLabel = 'Fair';
    } else {
      scoreColor = AppTheme.error;
      scoreLabel = 'Needs Improvement';
    }

    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircularProgressCard(
            progress: totalScore / 100,
            label: scoreLabel,
            centerText: '${totalScore.toInt()}',
            progressColor: scoreColor,
            size: 80,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScoreBreakdown(
                  context,
                  'Completion Rate',
                  '${completionRate.toStringAsFixed(0)}%',
                  0.8,
                ),
                const SizedBox(height: 8),
                _buildScoreBreakdown(
                  context,
                  'Streak Bonus',
                  '+$streakBonus',
                  0.2,
                ),
                const SizedBox(height: 12),
                Text(
                  'Keep up the great work! 💪',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[400] 
                        : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBreakdown(
    BuildContext context,
    String label,
    String value,
    double weight,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyChart(BuildContext context, WidgetRef ref, Map<String, dynamic> stats) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now().weekday - 1;

    // Compute per-day completion rates from real data
    final now = DateTime.now();
    // Find the Monday of this week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final List<double> dailyRates = [];
    try {
      final summaryRepo = ref.read(daySummaryRepositoryProvider);
      for (int i = 0; i < 7; i++) {
        final day = monday.add(Duration(days: i));
        final dateStr = DateHelper.formatDate(day);
        final summary = summaryRepo.getSummaryForDate(dateStr);
        if (summary != null && summary.totalTasks > 0) {
          dailyRates.add(summary.completedTasks / summary.totalTasks);
        } else {
          dailyRates.add(0.0);
        }
      }
    } catch (_) {
      // If repo not ready, fill with zeros
      while (dailyRates.length < 7) {
        dailyRates.add(0.0);
      }
    }

    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final isToday = index == today;
              // Use real completion rate; show a minimum sliver (0.1) for future/empty days
              final double height = dailyRates[index] > 0 ? dailyRates[index] : 0.1;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 100 * height,
                    decoration: BoxDecoration(
                      color: isToday 
                          ? AppTheme.primaryColor 
                          : (Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[600] 
                              : Colors.grey[400]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    days[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday 
                          ? AppTheme.primaryColor 
                          : (Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[400] 
                              : Colors.grey[600]),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeeklyStatItem(
                context,
                'Completed',
                '${stats['completedTasks'] ?? 0}',
                AppTheme.success,
              ),
              _buildWeeklyStatItem(
                context,
                'Missed',
                '${stats['missedTasks'] ?? 0}',
                AppTheme.error,
              ),
              _buildWeeklyStatItem(
                context,
                'Avg Load',
                (stats['averageDailyLoad'] as double? ?? 0).toStringAsFixed(1),
                AppTheme.info,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyStatItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
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

  Widget _buildTaskDistribution(BuildContext context, TaskState taskState) {
    final total = taskState.tasks.length;
    final completed = taskState.completedTasks.length;
    final pending = total - completed;
    final carriedOver = taskState.carriedOverTasks.length;

    if (total == 0) {
      return GradientCard(
        child: EmptyStateWidget(
          icon: Icons.pie_chart_outline,
          title: 'No Data',
          subtitle: 'Add tasks to see distribution',
        ),
      );
    }

    return GradientCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildDistributionItem(
                  context,
                  'Completed',
                  completed,
                  total,
                  AppTheme.success,
                ),
                const SizedBox(height: 12),
                _buildDistributionItem(
                  context,
                  'Pending',
                  pending,
                  total,
                  AppTheme.warning,
                ),
                const SizedBox(height: 12),
                _buildDistributionItem(
                  context,
                  'Carried Over',
                  carriedOver,
                  total,
                  Colors.amber,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionItem(
    BuildContext context,
    String label,
    int count,
    int total,
    Color color,
  ) {
    final percentage = total > 0 ? (count / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            Text(
              '$count (${percentage.toStringAsFixed(0)}%)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: color.withOpacity(0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }

  Widget _buildAchievements(BuildContext context, dynamic dashboard) {
    final streak = dashboard.streak as int;

    final achievements = [
      {
        'emoji': '🔥',
        'title': 'First Flame',
        'description': 'Complete 1 day streak',
        'unlocked': streak >= 1,
        'color': Colors.orange,
      },
      {
        'emoji': '⭐',
        'title': 'Week Warrior',
        'description': 'Maintain 7 day streak',
        'unlocked': streak >= 7,
        'color': Colors.amber,
      },
      {
        'emoji': '🏆',
        'title': 'Champion',
        'description': 'Maintain 30 day streak',
        'unlocked': streak >= 30,
        'color': Colors.blue,
      },
      {
        'emoji': '💎',
        'title': 'Diamond',
        'description': 'Maintain 100 day streak',
        'unlocked': streak >= 100,
        'color': Colors.purple,
      },
    ];

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: achievements.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final achievement = achievements[index];
          return SizedBox(
            width: 130,
            child: AchievementBadge(
              emoji: achievement['emoji'] as String,
              title: achievement['title'] as String,
              description: achievement['description'] as String,
              isUnlocked: achievement['unlocked'] as bool,
              color: achievement['color'] as Color,
            ),
          );
        },
      ),
    );
  }
}
