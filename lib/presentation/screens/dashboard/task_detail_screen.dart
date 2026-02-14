import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/estimation_mode.dart';
import '../../../data/models/reminder_type.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/task_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/custom_types_provider.dart';
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
  late String _selectedTypeId;
  late String _selectedPriorityId;
  late bool _isRecurring;
  late String? _recurringStartDate;
  late String? _recurringEndDate;
  DateTime? _alarmTime;
  int _reminderTypeIndex = 0;
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
    final customTypes = ref.read(customTypesProvider);
    _selectedTypeId = customTypes.taskTypes.isNotEmpty ? customTypes.taskTypes.first.id : 'task';
    _selectedPriorityId = customTypes.priorities.isNotEmpty ? customTypes.priorities.first.id : 'medium';
    _isRecurring = false;
    _recurringStartDate = null;
    _recurringEndDate = null;
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
      final customTypes = ref.read(customTypesProvider);
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
      _notesController.text = task.notes ?? '';
      _selectedHours = task.durationMinutes ~/ 60;
      _selectedMinutes = task.durationMinutes % 60;
      _selectedTypeId = customTypes.findTaskType(task.effectiveTypeId) != null
          ? task.effectiveTypeId
          : (customTypes.taskTypes.isNotEmpty ? customTypes.taskTypes.first.id : 'task');
      _selectedPriorityId = customTypes.findPriority(task.effectivePriorityId) != null
          ? task.effectivePriorityId
          : (customTypes.priorities.isNotEmpty ? customTypes.priorities.first.id : 'medium');
      _isRecurring = task.isRecurring;
      _recurringStartDate = task.recurringStartDate;
      _recurringEndDate = task.recurringEndDate;
      _alarmTime = task.alarmTime;
      _reminderTypeIndex = task.reminderTypeIndex;
      _controllersInitialized = true;
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
                      DateHelper.formatDateTime12h(task.completedAt!),
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
            final customTypes = ref.watch(customTypesProvider);
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _viewChip(customTypes.taskTypeLabelById(task.effectiveTypeId), Colors.purple),
                _viewChip(customTypes.priorityLabelById(task.effectivePriorityId), customTypes.priorityColorById(task.effectivePriorityId)),
                if (mode == EstimationMode.timeBased)
                  _viewChip(task.formattedDuration, AppTheme.info),
                if (task.isRecurring) _viewChip('Recurring', AppTheme.primaryColor),
                if (task.isCarriedOver) _viewChip('Carried Over', Colors.amber),
              ],
            );
          }),
          const SizedBox(height: 24),

          // Alarm
          if (task.alarmTime != null) ...[
            _sectionCard(
              icon: task.reminderType == ReminderType.fullAlarm ? Icons.alarm : Icons.notifications_outlined,
              iconColor: Colors.orange,
              title: task.reminderType == ReminderType.fullAlarm ? 'Alarm' : 'Notification',
              value: DateHelper.formatDateTime12h(task.alarmTime!),
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
                  child: DropdownButtonFormField<String>(
                    value: _selectedTypeId,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ref.watch(customTypesProvider).taskTypes.map((ct) {
                          return DropdownMenuItem(
                            value: ct.id,
                            child: Text(ct.label, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                    onChanged: (v) => setState(() => _selectedTypeId = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPriorityId,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ref.watch(customTypesProvider).priorities.map((cp) {
                          return DropdownMenuItem(
                            value: cp.id,
                            child: Text(cp.label, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                    onChanged: (v) => setState(() => _selectedPriorityId = v!),
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

            // Recurring toggle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.blue.withOpacity(0.3) : Colors.blue.withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.repeat, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recursive Task',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('Repeats within a date range',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                )),
                          ],
                        ),
                      ),
                      Switch(value: _isRecurring, onChanged: (v) {
                        setState(() {
                          _isRecurring = v;
                          if (v && _recurringStartDate == null) {
                            _recurringStartDate = DateHelper.formatDate(DateTime.now());
                            _recurringEndDate = DateHelper.formatDate(DateTime.now().add(const Duration(days: 30)));
                          }
                        });
                      }),
                    ],
                  ),
                  if (_isRecurring) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _recurringStartDate != null ? DateHelper.parseDate(_recurringStartDate!) : DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _recurringStartDate = DateHelper.formatDate(picked));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    _recurringStartDate != null
                                        ? DateHelper.formatDateForDisplay(DateHelper.parseDate(_recurringStartDate!))
                                        : 'From',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _recurringEndDate != null ? DateHelper.parseDate(_recurringEndDate!) : DateTime.now().add(const Duration(days: 30)),
                                firstDate: _recurringStartDate != null ? DateHelper.parseDate(_recurringStartDate!) : DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() => _recurringEndDate = DateHelper.formatDate(picked));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    _recurringEndDate != null
                                        ? DateHelper.formatDateForDisplay(DateHelper.parseDate(_recurringEndDate!))
                                        : 'To',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
              child: Column(
                children: [
                  Row(
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
                                  ? 'Set for ${DateHelper.formatDateTime12h(_alarmTime!)}'
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
                          onPressed: () async {
                            // Check if this is a recurring task being edited
                            final taskState = ref.read(taskStateProvider);
                            final task = taskState.tasks.firstWhere(
                              (t) => t.id == widget.taskId,
                              orElse: () => throw StateError('Task not found'),
                            );
                            
                            if (task.isRecurring) {
                              final choice = await _showRecurringAlarmDialog(context);
                              if (choice == null) return; // cancelled
                              
                              final notifier = ref.read(taskStateProvider.notifier);
                              if (choice == 'today') {
                                // Mute for today — keep alarmTime on entity for future days
                                notifier.muteAlarmForToday(task.id);
                                // Exit edit mode since we already applied the change
                                setState(() => _isEditing = false);
                                _controllersInitialized = false;
                              } else {
                                // Clear for all days
                                setState(() => _alarmTime = null);
                              }
                            } else {
                              setState(() => _alarmTime = null);
                            }
                          },
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
                  // Reminder type toggle — only shown when a time is set
                  if (_alarmTime != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _reminderTypeIndex = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _reminderTypeIndex == 0
                                    ? Colors.orange.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _reminderTypeIndex == 0
                                      ? Colors.orange
                                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.alarm, size: 16,
                                      color: _reminderTypeIndex == 0 ? Colors.orange : (isDark ? Colors.grey[400] : Colors.grey[600])),
                                  const SizedBox(width: 6),
                                  Text('Alarm',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _reminderTypeIndex == 0 ? FontWeight.w600 : FontWeight.w400,
                                        color: _reminderTypeIndex == 0 ? Colors.orange : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _reminderTypeIndex = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _reminderTypeIndex == 1
                                    ? Colors.blue.withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _reminderTypeIndex == 1
                                      ? Colors.blue
                                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.notifications_outlined, size: 16,
                                      color: _reminderTypeIndex == 1 ? Colors.blue : (isDark ? Colors.grey[400] : Colors.grey[600])),
                                  const SizedBox(width: 6),
                                  Text('Notification',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _reminderTypeIndex == 1 ? FontWeight.w600 : FontWeight.w400,
                                        color: _reminderTypeIndex == 1 ? Colors.blue : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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

    // Check overlay permission if alarm set AND reminder type is full alarm
    var effectiveAlarmTime = _alarmTime;
    if (_alarmTime != null && _reminderTypeIndex == 0) {
      final hasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
      if (!hasOverlay) {
        await ref.read(notificationServiceProvider).ensureAlarmPermissions(context);
        final nowHasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
        if (!nowHasOverlay) {
          effectiveAlarmTime = null;
        }
      }
    }

    final customTypes = ref.read(customTypesProvider);
    ref.read(taskStateProvider.notifier).updateTask(task.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      durationMinutes: durationMinutes,
      taskType: customTypes.resolveTaskTypeEnum(_selectedTypeId),
      priority: customTypes.resolvePriorityEnum(_selectedPriorityId),
      taskTypeId: _selectedTypeId,
      priorityId: _selectedPriorityId,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      isRecurring: _isRecurring,
      recurringStartDate: _isRecurring ? _recurringStartDate : null,
      recurringEndDate: _isRecurring ? _recurringEndDate : null,
      alarmTime: effectiveAlarmTime,
      reminderTypeIndex: _reminderTypeIndex,
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

  // ─── ESTIMATION FIELDS ──────────────────────────────────────────────

  List<Widget> _buildEstimationFields(bool isDark) {
    final mode = ref.watch(settingsProvider).estimationMode;

    if (mode == EstimationMode.timeBased) {
      return [
        Text(
          'Duration *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedHours,
                decoration: const InputDecoration(
                  labelText: 'Hours',
                  prefixIcon: Icon(Icons.schedule),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: List.generate(25, (i) => i)
                    .map((h) => DropdownMenuItem(value: h, child: Text('$h h', style: const TextStyle(fontSize: 14))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedHours = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedMinutes,
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  prefixIcon: Icon(Icons.timer),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m m', style: const TextStyle(fontSize: 14))))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMinutes = v!),
                validator: (v) {
                  if (_selectedHours == 0 && (v == null || v == 0)) return 'Duration required';
                  return null;
                },
              ),
            ),
          ],
        ),
      ];
    } else {
      // Count-based — no extra fields
      return [];
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

  /// Show dialog asking whether to delete alarm for today only or all upcoming days
  Future<String?> _showRecurringAlarmDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.alarm_off, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Remove Alarm', style: TextStyle(fontSize: 18))),
          ],
        ),
        content: const Text(
          'This is a recurring task. Would you like to remove the alarm for today only, or for all upcoming days?',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('today'),
            child: const Text('Today Only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('All Days'),
          ),
        ],
      ),
    );
  }
}
