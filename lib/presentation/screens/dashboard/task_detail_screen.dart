import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/task_type.dart';
import '../../../data/models/task_priority.dart';
import '../../../data/models/estimation_mode.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/task_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/providers.dart';

/// Full-page Task Detail screen with view and edit modes.
class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  bool _isEditing = false;

  // Edit controllers — initialized from task in didChangeDependencies
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  late int _selectedHours;
  late int _selectedMinutes;
  late TaskType _selectedType;
  late TaskPriority _selectedPriority;
  late bool _isPermanent;
  late int _selectedWeight;
  DateTime? _alarmTime;
  final _formKey = GlobalKey<FormState>();
  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _notesController = TextEditingController();
    _selectedHours = 0;
    _selectedMinutes = 30;
    _selectedType = TaskType.task;
    _selectedPriority = TaskPriority.medium;
    _isPermanent = false;
    _selectedWeight = 1;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initFromTask(TaskEntity task) {
    if (!_controllersInitialized) {
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
      _notesController.text = task.notes ?? '';
      _selectedHours = task.durationMinutes ~/ 60;
      _selectedMinutes = task.durationMinutes % 60;
      _selectedType = task.taskType;
      _selectedPriority = task.priority;
      _isPermanent = task.isPermanent;
      _selectedWeight = task.weight;
      _alarmTime = task.alarmTime;
      _controllersInitialized = true;
    }
  }

  TaskEntity? _findTask() {
    final tasks = ref.read(taskStateProvider).tasks;
    try {
      return tasks.firstWhere((t) => t.id == widget.taskId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskStateProvider);
    TaskEntity? task;
    try {
      task = taskState.tasks.firstWhere((t) => t.id == widget.taskId);
    } catch (_) {
      task = null;
    }

    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }

    _initFromTask(task);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Task' : 'Task Details'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.error),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(task!),
            ),
        ],
      ),
      body: _isEditing ? _buildEditMode(task, isDark) : _buildViewMode(task, isDark),
    );
  }

  // ─── VIEW MODE ─────────────────────────────────────────────────────

  Widget _buildViewMode(TaskEntity task, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status banner
          if (task.isCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Completed',
                    style: TextStyle(
                      color: AppTheme.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (task.completedAt != null) ...[
                    const Spacer(),
                    Text(
                      '${task.completedAt!.hour.toString().padLeft(2, '0')}:${task.completedAt!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: AppTheme.success.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Title
          Text(
            task.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          const SizedBox(height: 16),

          // Tags
          Builder(builder: (_) {
            final mode = ref.watch(settingsProvider).estimationMode;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _viewChip(task.taskType.label, Colors.purple),
                _viewChip(task.priority.label, task.priority.color),
                if (mode == EstimationMode.timeBased)
                  _viewChip(task.formattedDuration, AppTheme.info),
                if (mode == EstimationMode.weightBased)
                  _viewChip(task.formattedWeight, AppTheme.info),
                if (task.isPermanent) _viewChip('Permanent', AppTheme.primaryColor),
                if (task.isCarriedOver) _viewChip('Carried Over', Colors.amber),
              ],
            );
          }),
          const SizedBox(height: 24),

          // Alarm
          if (task.alarmTime != null) ...[
            _sectionCard(
              icon: Icons.alarm,
              iconColor: Colors.orange,
              title: 'Reminder',
              value:
                  '${task.alarmTime!.hour.toString().padLeft(2, '0')}:${task.alarmTime!.minute.toString().padLeft(2, '0')}',
              isDark: isDark,
            ),
            const SizedBox(height: 16),
          ],

          // Description
          if (task.description != null && task.description!.isNotEmpty) ...[
            _sectionHeader('Description', isDark),
            const SizedBox(height: 8),
            Text(task.description!, style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: 24),
          ],

          // Notes
          if (task.notes != null && task.notes!.isNotEmpty) ...[
            _sectionHeader('Notes', isDark),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(task.notes!, style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
            const SizedBox(height: 24),
          ],

          // Dates info
          _sectionHeader('Info', isDark),
          const SizedBox(height: 8),
          _infoRow('Created', DateHelper.formatDateForDisplay(DateHelper.parseDate(task.createdDate)), isDark),
          if (task.originalDate != task.currentDate)
            _infoRow('Original date', DateHelper.formatDateForDisplay(DateHelper.parseDate(task.originalDate)), isDark),
          _infoRow('Scheduled for', DateHelper.formatDateForDisplay(DateHelper.parseDate(task.currentDate)), isDark),

          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(taskStateProvider.notifier).toggleTaskCompletion(task.id);
                  },
                  icon: Icon(task.isCompleted ? Icons.undo : Icons.check_circle_outline),
                  label: Text(task.isCompleted ? 'Mark Incomplete' : 'Mark Complete'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── EDIT MODE ─────────────────────────────────────────────────────

  Widget _buildEditMode(TaskEntity task, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task Title *',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Type & Priority
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TaskType>(
                    value: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TaskType.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedType = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TaskPriority>(
                    value: _selectedPriority,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TaskPriority.values
                        .map((p) => DropdownMenuItem(value: p, child: Text(p.label, style: const TextStyle(fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPriority = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Estimation fields (mode-aware)
            ..._buildEstimationFields(isDark),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Permanent toggle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.blue.withOpacity(0.3) : Colors.blue.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.repeat, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Permanent Task',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('Shows up every day until deleted',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            )),
                      ],
                    ),
                  ),
                  Switch(value: _isPermanent, onChanged: (v) => setState(() => _isPermanent = v)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Alarm
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.orange.withOpacity(0.1) : Colors.orange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.orange.withOpacity(0.3) : Colors.orange.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reminder',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _alarmTime != null
                              ? 'Set for ${_alarmTime!.hour.toString().padLeft(2, '0')}:${_alarmTime!.minute.toString().padLeft(2, '0')}'
                              : 'No reminder set',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_alarmTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _alarmTime = null),
                    ),
                  IconButton(
                    icon: const Icon(Icons.access_time),
                    onPressed: () async {
                      final selectedDate = DateHelper.parseDate(ref.read(taskStateProvider).selectedDate);
                      final initial = _alarmTime != null
                          ? TimeOfDay(hour: _alarmTime!.hour, minute: _alarmTime!.minute)
                          : TimeOfDay.now();
                      final time = await showTimePicker(context: context, initialTime: initial);
                      if (time != null) {
                        setState(() {
                          _alarmTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, time.hour, time.minute);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Save / Cancel buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Reset controllers from task and exit edit mode
                      _controllersInitialized = false;
                      _initFromTask(task);
                      setState(() => _isEditing = false);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveTask(task),
                    icon: const Icon(Icons.save),
                    label: const Text('Update'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── SAVE ──────────────────────────────────────────────────────────

  Future<void> _saveTask(TaskEntity task) async {
    if (!_formKey.currentState!.validate()) return;

    final mode = ref.read(settingsProvider).estimationMode;
    int durationMinutes;

    if (mode == EstimationMode.timeBased) {
      durationMinutes = (_selectedHours * 60) + _selectedMinutes;
      if (durationMinutes < 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duration must be at least 5 minutes'), backgroundColor: AppTheme.warning),
        );
        return;
      }
      if (durationMinutes > 24 * 60) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duration cannot exceed 24 hours'), backgroundColor: AppTheme.warning),
        );
        return;
      }
    } else {
      durationMinutes = task.durationMinutes; // keep existing
    }

    // Check overlay permission if alarm set
    var effectiveAlarmTime = _alarmTime;
    if (_alarmTime != null) {
      final hasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
      if (!hasOverlay) {
        await ref.read(notificationServiceProvider).ensureAlarmPermissions(context);
        final nowHasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
        if (!nowHasOverlay) {
          effectiveAlarmTime = null;
        }
      }
    }

    ref.read(taskStateProvider.notifier).updateTask(task.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      durationMinutes: durationMinutes,
      taskType: _selectedType,
      priority: _selectedPriority,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      isPermanent: _isPermanent,
      alarmTime: effectiveAlarmTime,
      weight: _selectedWeight,
    ));

    setState(() => _isEditing = false);
    _controllersInitialized = false; // Reload from updated task on next build

    if (_alarmTime != null && effectiveAlarmTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task updated without alarm — "Display over other apps" permission required.'),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Task updated!'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ─── DELETE ─────────────────────────────────────────────────────────

  Future<void> _confirmDelete(TaskEntity task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(taskStateProvider.notifier).deleteTask(task.id);
      Navigator.pop(context); // Go back to task list
    }
  }

  // ─── HELPERS ───────────────────────────────────────────────────────

  Widget _viewChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(isDark ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.grey[300] : Colors.grey[700])),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: iconColor)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}
