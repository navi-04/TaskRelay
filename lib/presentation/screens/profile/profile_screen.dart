import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/custom_types_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../widgets/common_widgets.dart';
import '../../../data/models/custom_task_type.dart';
import '../../../data/models/estimation_mode.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int? _selectedHours;
  int? _selectedMinutes;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final dashboard = ref.watch(dashboardProvider);

    // Initialize hours and minutes from settings only once
    if (!_initialized) {
      _selectedHours = settings.dailyTimeLimitMinutes ~/ 60;
      // Round minutes to nearest valid option (0, 15, 30, 45)
      final rawMinutes = settings.dailyTimeLimitMinutes % 60;
      _selectedMinutes = (rawMinutes ~/ 15) * 15;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Stats
            _buildQuickStats(context, dashboard),
            const SizedBox(height: 24),

            // Settings Section
            _buildSectionHeader(context, 'Settings', Icons.settings),
            const SizedBox(height: 12),

            // Estimation Mode & Limits
            _buildEstimationModeCard(context, settings),
            const SizedBox(height: 12),

            // Notifications Card
            _buildNotificationsCard(context, settings),
            const SizedBox(height: 12),

            // Appearance Card
            _buildAppearanceCard(context, settings),
            const SizedBox(height: 24),

            // Information Section
            _buildSectionHeader(context, 'Information', Icons.info_outline),
            const SizedBox(height: 12),

            // Task Types Card
            _buildTaskTypesCard(context, settings),
            const SizedBox(height: 12),

            // About Card
            _buildAboutCard(context),
            const SizedBox(height: 24),
            
            // Danger Zone Section
            _buildSectionHeader(context, 'Danger Zone', Icons.warning_amber),
            const SizedBox(height: 12),
            
            // Danger Zone Card
            _buildDangerZoneCard(context),
            const SizedBox(height: 24),

            const SizedBox(height: 100),
          ],
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
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
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

  Widget _buildQuickStats(BuildContext context, dynamic dashboard) {
    final completionRate = dashboard.weeklyStats['completionPercentage'] as double? ?? 0.0;
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            'Streak',
            '${dashboard.streak}',
            'days',
            Icons.local_fire_department,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            context,
            'Completion',
            '${completionRate.toInt()}',
            '%',
            Icons.pie_chart,
            AppTheme.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            context,
            'Daily Limit',
            dashboard.formattedDailyLimitValue,
            '',
            Icons.schedule,
            AppTheme.info,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    String suffix,
    IconData icon,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  suffix,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                  ),
                ),
              ),
            ],
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

  Widget _buildTimeLimitSection(BuildContext context, settings) {
    final currentHours = _selectedHours ?? (settings.dailyTimeLimitMinutes ~/ 60);
    final rawMinutes = settings.dailyTimeLimitMinutes % 60;
    final currentMinutes = _selectedMinutes ?? ((rawMinutes ~/ 15) * 15);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Daily Time Limit',
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
            Expanded(
              child: DropdownButtonFormField<int>(
                value: currentHours.clamp(0, 24),
                decoration: const InputDecoration(
                  labelText: 'Hours',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: List.generate(25, (index) => index).map((hour) {
                  return DropdownMenuItem(
                    value: hour,
                    child: Text('$hour h'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedHours = value!;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: currentMinutes,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [0, 15, 30, 45].map((minute) {
                  return DropdownMenuItem(
                    value: minute,
                    child: Text('$minute m'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMinutes = value!;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => _updateTimeLimit(_selectedHours ?? currentHours, _selectedMinutes ?? currentMinutes),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEstimationModeCard(BuildContext context, settings) {
    final currentMode = settings.estimationMode as EstimationMode;
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bar_chart, color: Colors.deepPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimation Mode',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      currentMode.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Mode selector
          SegmentedButton<EstimationMode>(
            segments: EstimationMode.values.map((mode) {
              return ButtonSegment<EstimationMode>(
                value: mode,
                label: Text(
                  mode == EstimationMode.timeBased
                      ? 'Time'
                      : 'Count',
                  style: const TextStyle(fontSize: 13),
                ),
                icon: Icon(
                  mode == EstimationMode.timeBased
                      ? Icons.schedule
                      : Icons.format_list_numbered,
                  size: 18,
                ),
              );
            }).toList(),
            selected: {currentMode},
            onSelectionChanged: (Set<EstimationMode> selected) {
              final newMode = selected.first;
              ref.read(settingsProvider.notifier).updateEstimationMode(newMode.index);
            },
          ),
          const SizedBox(height: 16),
          // Conditional limit input based on mode
          if (currentMode == EstimationMode.timeBased)
            _buildTimeLimitSection(context, settings),
          if (currentMode == EstimationMode.countBased)
            _buildLimitRow(
              context,
              label: 'Daily Task Limit',
              value: settings.dailyCountLimit as int,
              suffix: 'tasks',
              min: 1,
              max: 100,
              onSave: (v) => ref.read(settingsProvider.notifier).updateDailyCountLimit(v),
            ),
        ],
      ),
    );
  }

  Widget _buildLimitRow(
    BuildContext context, {
    required String label,
    required int value,
    required String suffix,
    required int min,
    required int max,
    required void Function(int) onSave,
  }) {
    final controller = TextEditingController(text: value.toString());
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () {
            final v = int.tryParse(controller.text);
            if (v != null && v >= min && v <= max) {
              onSave(v);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label updated to $v $suffix'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Enter a value between $min and $max'),
                  backgroundColor: AppTheme.warning,
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildNotificationsCard(BuildContext context, settings) {
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications, color: AppTheme.warning),
              ),
              const SizedBox(width: 12),
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsTile(
            context,
            'Daily Reminders',
            'Get notified about pending tasks',
            Icons.alarm,
            trailing: Switch(
              value: settings.notificationsEnabled,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).updateNotificationSettings(
                  enabled: value,
                  hour: settings.notificationHour,
                  minute: settings.notificationMinute,
                );
              },
            ),
          ),
          if (settings.notificationsEnabled) ...[
            const Divider(),
            _buildSettingsTile(
              context,
              'Reminder Time',
              '${settings.notificationHour.toString().padLeft(2, '0')}:${settings.notificationMinute.toString().padLeft(2, '0')}',
              Icons.access_time,
              onTap: _selectNotificationTime,
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
          const Divider(),
          _buildSettingsTile(
            context,
            'Carry-Over Alerts',
            'Alert when tasks are carried over',
            Icons.arrow_forward,
            trailing: Switch(
              value: settings.showCarryOverAlerts,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).toggleCarryOverAlerts();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, settings) {
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.palette, color: Colors.purple),
              ),
              const SizedBox(width: 12),
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSettingsTile(
            context,
            'Dark Mode',
            settings.isDarkMode ? 'Currently using dark theme' : 'Currently using light theme',
            settings.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            trailing: Switch(
              value: settings.isDarkMode,
              onChanged: (value) {
                ref.read(settingsProvider.notifier).toggleDarkMode();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon, {
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey[400] 
                : Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTypesCard(BuildContext context, settings) {
    final customTypes = ref.watch(customTypesProvider);
    
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.category, color: AppTheme.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Task Types & Priorities',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Task Types Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Task Types',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[400] 
                      : Colors.grey[600],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddTaskTypeDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: customTypes.taskTypes.map((type) => 
              _buildEditableTypeChip(context, type)
            ).toList(),
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          
          // Priorities Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Priorities',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[400] 
                      : Colors.grey[600],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddPriorityDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: customTypes.priorities.map((priority) => 
              _buildEditablePriorityChip(context, priority)
            ).toList(),
          ),
          
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => _showResetTypesConfirmation(context),
              icon: const Icon(Icons.restore, size: 16, color: Colors.grey),
              label: Text(
                'Reset to Defaults',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[400] 
                        : Colors.grey[600], 
                    fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEditableTypeChip(BuildContext context, CustomTaskType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showEditTaskTypeDialog(context, type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? Colors.grey[600]! : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type.label,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _showDeleteTaskTypeDialog(context, type),
              child: Icon(Icons.close, size: 14, color: isDark ? Colors.grey[400] : Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEditablePriorityChip(BuildContext context, CustomPriority priority) {
    final color = Color(priority.colorValue);
    return GestureDetector(
      onTap: () => _showEditPriorityDialog(context, priority),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              priority.label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _showDeletePriorityDialog(context, priority),
              child: Icon(Icons.close, size: 14, color: color.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showAddTaskTypeDialog(BuildContext context) {
    final labelController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Task Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'Enter type name',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (labelController.text.isNotEmpty) {
                ref.read(customTypesProvider.notifier).addTaskType(
                  labelController.text,
                  '📌',
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Task type "${labelController.text}" added'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
  
  void _showEditTaskTypeDialog(BuildContext context, CustomTaskType type) {
    final labelController = TextEditingController(text: type.label);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (labelController.text.isNotEmpty) {
                ref.read(customTypesProvider.notifier).updateTaskType(
                  type.id,
                  labelController.text,
                  type.emoji,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Task type updated'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteTaskTypeDialog(BuildContext context, CustomTaskType type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task Type'),
        content: Text('Are you sure you want to delete "${type.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted = await ref.read(customTypesProvider.notifier).deleteTaskType(type.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(deleted 
                    ? 'Task type deleted' 
                    : 'Cannot delete - at least one type required'),
                  backgroundColor: deleted ? AppTheme.success : AppTheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  void _showAddPriorityDialog(BuildContext context) {
    final labelController = TextEditingController();
    int selectedColorValue = 0xFF9E9E9E; // Grey default

    final colors = [
      {'name': 'Blue', 'value': 0xFF2196F3},
      {'name': 'Green', 'value': 0xFF4CAF50},
      {'name': 'Orange', 'value': 0xFFFF9800},
      {'name': 'Red', 'value': 0xFFF44336},
      {'name': 'Purple', 'value': 0xFF9C27B0},
      {'name': 'Pink', 'value': 0xFFE91E63},
      {'name': 'Teal', 'value': 0xFF009688},
      {'name': 'Grey', 'value': 0xFF9E9E9E},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Priority'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Enter priority name',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((c) {
                  final color = Color(c['value'] as int);
                  final isSelected = selectedColorValue == c['value'];
                  return GestureDetector(
                    onTap: () => setState(() => selectedColorValue = c['value'] as int),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                      ),
                      child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.isNotEmpty) {
                  ref.read(customTypesProvider.notifier).addPriority(
                    labelController.text,
                    '⭐',
                    selectedColorValue,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Priority "${labelController.text}" added'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showEditPriorityDialog(BuildContext context, CustomPriority priority) {
    final labelController = TextEditingController(text: priority.label);
    int selectedColorValue = priority.colorValue;

    final colors = [
      {'name': 'Blue', 'value': 0xFF2196F3},
      {'name': 'Green', 'value': 0xFF4CAF50},
      {'name': 'Orange', 'value': 0xFFFF9800},
      {'name': 'Red', 'value': 0xFFF44336},
      {'name': 'Purple', 'value': 0xFF9C27B0},
      {'name': 'Pink', 'value': 0xFFE91E63},
      {'name': 'Teal', 'value': 0xFF009688},
      {'name': 'Grey', 'value': 0xFF9E9E9E},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Priority'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text('Color', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((c) {
                  final color = Color(c['value'] as int);
                  final isSelected = selectedColorValue == c['value'];
                  return GestureDetector(
                    onTap: () => setState(() => selectedColorValue = c['value'] as int),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                      ),
                      child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.isNotEmpty) {
                  ref.read(customTypesProvider.notifier).updatePriority(
                    priority.id,
                    labelController.text,
                    priority.emoji,
                    selectedColorValue,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Priority updated'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showDeletePriorityDialog(BuildContext context, CustomPriority priority) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Priority'),
        content: Text('Are you sure you want to delete "${priority.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted = await ref.read(customTypesProvider.notifier).deletePriority(priority.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(deleted 
                    ? 'Priority deleted' 
                    : 'Cannot delete - at least one priority required'),
                  backgroundColor: deleted ? AppTheme.success : AppTheme.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  void _showResetTypesConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all task types and priorities to their default values. Custom types will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(customTypesProvider.notifier).resetAll();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Types and priorities reset to defaults'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.info, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              Text(
                'About',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(context, 'Version', '1.0.0'),
          _buildInfoRow(context, 'Architecture', 'Clean Architecture + MVVM'),
          _buildInfoRow(context, 'State', 'Riverpod'),
          _buildInfoRow(context, 'Database', 'Hive (Offline-First)'),
          // ...existing code...
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[400] 
                  : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDangerZoneCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_forever, color: AppTheme.error),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Tasks',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.error,
                      ),
                    ),
                    Text(
                      'Permanently delete tasks within a date range',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Delete by date range
          _buildDangerButton(
            context,
            icon: Icons.date_range,
            label: 'Delete Tasks in Date Range',
            subtitle: 'Select start and end date to delete',
            onTap: () => _showDeleteByDateRangeDialog(context),
          ),
          const SizedBox(height: 12),
          
          // Delete all tasks
          _buildDangerButton(
            context,
            icon: Icons.delete_sweep,
            label: 'Delete All Tasks',
            subtitle: 'Remove all tasks permanently',
            onTap: () => _showDeleteAllTasksDialog(context),
            isDestructive: true,
          ),
          const SizedBox(height: 12),
          
          // Clear all app data
          _buildDangerButton(
            context,
            icon: Icons.warning_amber,
            label: 'Clear All App Data',
            subtitle: 'Reset everything including settings',
            onTap: () => _showClearAllAppDataDialog(context),
            isDestructive: true,
          ),
        ],
      ),
    );
  }
  
  Widget _buildDangerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDestructive 
            ? AppTheme.error.withOpacity(0.1) 
            : (isDark ? Colors.grey[800] : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDestructive 
              ? AppTheme.error.withOpacity(0.5) 
              : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon, 
              color: isDestructive ? AppTheme.error : (isDark ? Colors.grey[400] : Colors.grey[700]),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? AppTheme.error : (isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDestructive ? AppTheme.error : (isDark ? Colors.grey[500] : Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showDeleteByDateRangeDialog(BuildContext context) {
    DateTime startDate = DateTime.now().subtract(const Duration(days: 7));
    DateTime endDate = DateTime.now();
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          // Calculate count inside builder to ensure it's always fresh
          final startStr = DateHelper.formatDate(startDate);
          final endStr = DateHelper.formatDate(endDate);
          final tasks = ref.read(taskStateProvider.notifier).getTasksInDateRange(startStr, endStr);
          final taskCount = tasks.length;
          
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.date_range, color: AppTheme.error),
                const SizedBox(width: 8),
                const Text('Delete by Date Range'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select the date range to delete tasks:',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  // Start Date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          startDate = picked;
                          if (startDate.isAfter(endDate)) {
                            endDate = startDate;
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('From', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text(
                                  DateHelper.formatDateForDisplay(startDate),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit, color: Colors.grey, size: 18),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // End Date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          endDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('To', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text(
                                  DateHelper.formatDateForDisplay(endDate),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.edit, color: Colors.grey, size: 18),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // Task count preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: taskCount > 0 
                        ? AppTheme.error.withOpacity(0.1) 
                        : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          taskCount > 0 ? Icons.warning : Icons.check_circle,
                          color: taskCount > 0 ? AppTheme.error : AppTheme.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            taskCount > 0 
                              ? '$taskCount task(s) will be deleted'
                              : 'No tasks in this date range',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: taskCount > 0 ? AppTheme.error : AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: taskCount > 0 ? () {
                  Navigator.pop(dialogContext);
                  _confirmDeleteInRange(context, startDate, endDate, taskCount);
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _confirmDeleteInRange(BuildContext context, DateTime startDate, DateTime endDate, int count) {
    final startStr = DateHelper.formatDate(startDate);
    final endStr = DateHelper.formatDate(endDate);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppTheme.error),
            SizedBox(width: 8),
            Text('Confirm Deletion'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete $count task(s)?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Date range: ${DateHelper.formatDateForDisplay(startDate)} to ${DateHelper.formatDateForDisplay(endDate)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.error),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final deletedCount = await ref
                  .read(taskStateProvider.notifier)
                  .deleteTasksInDateRange(startStr, endStr);
              
              ref.invalidate(dashboardProvider);
              
              Navigator.pop(dialogContext);
              
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Deleted $deletedCount task(s)'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
  
  void _showDeleteAllTasksDialog(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: AppTheme.error),
            SizedBox(width: 8),
            Text('Delete All Tasks'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning_amber, color: AppTheme.error, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'This will permanently delete ALL tasks from the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This action cannot be undone!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.error),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(taskStateProvider.notifier).clearAllTasks();
              ref.invalidate(dashboardProvider);
              
              Navigator.pop(dialogContext);
              
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('All tasks have been deleted'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
  
  void _showClearAllAppDataDialog(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: AppTheme.error),
            SizedBox(width: 8),
            Text('Clear All Data'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.dangerous, color: AppTheme.error, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'COMPLETE DATA RESET',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppTheme.error,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'This will permanently delete:',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• All tasks\n• All day summaries\n• All statistics\n• All custom types & priorities\n• All settings',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'The app will restart with factory defaults.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'THIS CANNOT BE UNDONE!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Clear all tasks
              await ref.read(taskStateProvider.notifier).clearAllTasks();
              
              // Clear all day summaries
              await ref.read(daySummaryLocalDataSourceProvider).clearAllSummaries();
              
              // Reset custom types and priorities to defaults
              await ref.read(customTypesProvider.notifier).resetAll();
              
              // Reset settings to defaults
              await ref.read(settingsProvider.notifier).resetToDefaults();
              
              // Invalidate all providers to refresh
              ref.invalidate(dashboardProvider);
              ref.invalidate(taskStateProvider);
              ref.invalidate(customTypesProvider);
              ref.invalidate(settingsProvider);
              
              Navigator.pop(dialogContext);
              
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('All app data has been cleared'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[900],
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
  }

  void _updateTimeLimit(int hours, int minutes) {
    final totalMinutes = (hours * 60) + minutes;
    
    if (totalMinutes < 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Minimum time limit is 30 minutes'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    
    if (totalMinutes > 24 * 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Maximum time limit is 24 hours'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    
    ref.read(settingsProvider.notifier).updateDailyTimeLimit(totalMinutes);
    
    // Update local state to reflect the saved value
    setState(() {
      _selectedHours = hours;
      _selectedMinutes = minutes;
    });

    // Format display
    String timeStr;
    if (hours > 0 && minutes > 0) {
      timeStr = '${hours}h ${minutes}m';
    } else if (hours > 0) {
      timeStr = '${hours}h';
    } else {
      timeStr = '${minutes}m';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Daily time limit updated to $timeStr'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _selectNotificationTime() async {
    final settings = ref.read(settingsProvider);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.notificationHour,
        minute: settings.notificationMinute,
      ),
    );

    if (picked != null) {
      ref.read(settingsProvider.notifier).updateNotificationSettings(
        enabled: settings.notificationsEnabled,
        hour: picked.hour,
        minute: picked.minute,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reminder time set to ${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}
