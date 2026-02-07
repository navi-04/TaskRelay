import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/dashboard_provider.dart';
import '../../../data/models/day_summary_entity.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'daily_task_screen.dart';

/// Calendar Screen - Monthly view with task completion status
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  @override
  Widget build(BuildContext context) {
    final calendarData = ref.watch(calendarDataProvider(_focusedDay));
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Calendar Legend
          _buildLegend(context),
          const Divider(),
          
          // Calendar
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2030),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            
            // Calendar styling
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
              outsideDaysVisible: false,
              weekendTextStyle: TextStyle(
                color: Theme.of(context).colorScheme.error.withOpacity(0.7),
              ),
            ),
            
            // Header styling
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: Theme.of(context).colorScheme.primary,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            
            // Days of week styling
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              weekendStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.error.withOpacity(0.7),
              ),
            ),
            
            // Day builder with custom styling based on completion status
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _buildCalendarDay(context, day, calendarData);
              },
              todayBuilder: (context, day, focusedDay) {
                return _buildCalendarDay(context, day, calendarData, isToday: true);
              },
              selectedBuilder: (context, day, focusedDay) {
                return _buildCalendarDay(context, day, calendarData, isSelected: true);
              },
            ),
            
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              
              // Navigate to daily task screen for selected date
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DailyTaskScreen(
                    selectedDate: DateHelper.formatDate(selectedDay),
                  ),
                ),
              );
            },
            
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
          ),
          
          const Divider(),
          
          // Month Summary
          _buildMonthSummary(context, calendarData),
        ],
      ),
    );
  }
  
  Widget _buildLegend(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem(context, 'Completed', AppTheme.success),
          _buildLegendItem(context, 'Partial', AppTheme.warning),
          _buildLegendItem(context, 'Missed', AppTheme.error),
          _buildLegendItem(context, 'No Tasks', 
              Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[600]! 
                  : Colors.grey[300]!),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
  
  Widget _buildCalendarDay(
    BuildContext context,
    DateTime day,
    Map<String, DaySummaryEntity> calendarData, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    final dateString = DateHelper.formatDate(day);
    final summary = calendarData[dateString];
    
    Color? backgroundColor;
    Color? borderColor;
    
    // Determine background color based on status
    if (summary != null && summary.hasTasks) {
      switch (summary.dayStatus) {
        case DayStatus.completed:
          backgroundColor = AppTheme.success.withOpacity(0.8);
          break;
        case DayStatus.partial:
          backgroundColor = AppTheme.warning.withOpacity(0.8);
          break;
        case DayStatus.missed:
          backgroundColor = AppTheme.error.withOpacity(0.8);
          break;
        case DayStatus.noTasks:
          backgroundColor = null;
          break;
      }
    }
    
    // Override with selection/today colors
    if (isSelected) {
      borderColor = Theme.of(context).colorScheme.primary;
    } else if (isToday) {
      borderColor = Theme.of(context).colorScheme.primary.withOpacity(0.5);
    }
    
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: backgroundColor != null ? Colors.white : null,
            fontWeight: isToday || isSelected ? FontWeight.bold : null,
          ),
        ),
      ),
    );
  }
  
  Widget _buildMonthSummary(
    BuildContext context,
    Map<String, DaySummaryEntity> calendarData,
  ) {
    final summaries = calendarData.values.toList();
    
    final daysWithTasks = summaries.where((s) => s.hasTasks).length;
    final completedDays = summaries.where((s) => s.isFullyCompleted).length;
    final partialDays = summaries.where((s) => 
        s.hasTasks && s.completedTasks > 0 && !s.isFullyCompleted).length;
    final missedDays = summaries.where((s) => 
        s.hasTasks && s.completedTasks == 0).length;
    
    final totalTasks = summaries.fold(0, (sum, s) => sum + s.totalTasks);
    final completedTasks = summaries.fold(0, (sum, s) => sum + s.completedTasks);
    
    final completionRate = totalTasks > 0 
        ? (completedTasks / totalTasks) * 100 
        : 0.0;
    
    return Flexible(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        child: GradientCard(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.secondary.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Month Summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStatCard(
                      context,
                      'Done',
                      completedDays.toString(),
                      AppTheme.success,
                      Icons.check_circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildMiniStatCard(
                      context,
                      'Partial',
                      partialDays.toString(),
                      AppTheme.warning,
                      Icons.timelapse,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildMiniStatCard(
                      context,
                      'Missed',
                      missedDays.toString(),
                      AppTheme.error,
                      Icons.cancel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Completion Rate',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$completedTasks / $totalTasks',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${completionRate.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMiniStatCard(
    BuildContext context,
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    dynamic value, [
    Color? color,
  ]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
