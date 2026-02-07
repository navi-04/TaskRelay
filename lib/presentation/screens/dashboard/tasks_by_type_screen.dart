import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../providers/providers.dart';
import '../../providers/task_provider.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/task_type.dart';
import '../../../data/models/task_priority.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';

/// Screen that displays tasks categorized by their task type
class TasksByTypeScreen extends ConsumerStatefulWidget {
  const TasksByTypeScreen({super.key});

  @override
  ConsumerState<TasksByTypeScreen> createState() => _TasksByTypeScreenState();
}

class _TasksByTypeScreenState extends ConsumerState<TasksByTypeScreen> {
  String _searchQuery = '';
  final Map<TaskType, bool> _expandedSections = {};

  @override
  Widget build(BuildContext context) {
    final taskRepository = ref.watch(taskRepositoryProvider);
    final allTasks = taskRepository.getAllTasks();

    // Apply search filter
    var filteredTasks = allTasks.where((task) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesTitle = task.title.toLowerCase().contains(query);
        final matchesDescription = task.description?.toLowerCase().contains(query) ?? false;
        return matchesTitle || matchesDescription;
      }
      return true;
    }).toList();

    // Group tasks by type
    final Map<TaskType, List<TaskEntity>> tasksByType = {};
    for (final task in filteredTasks) {
      if (!tasksByType.containsKey(task.taskType)) {
        tasksByType[task.taskType] = [];
      }
      tasksByType[task.taskType]!.add(task);
    }

    // Sort types that have tasks
    final sortedTypes = tasksByType.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    // Initialize expanded state for new types
    for (final type in sortedTypes) {
      _expandedSections.putIfAbsent(type, () => true);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks by Type'),
        actions: [
          // Expand/Collapse all button
          IconButton(
            icon: Icon(
              _expandedSections.values.every((v) => v)
                  ? Icons.unfold_less
                  : Icons.unfold_more,
            ),
            tooltip: _expandedSections.values.every((v) => v)
                ? 'Collapse All'
                : 'Expand All',
            onPressed: () {
              setState(() {
                final expandAll = !_expandedSections.values.every((v) => v);
                for (final type in sortedTypes) {
                  _expandedSections[type] = expandAll;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search tasks...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          // Tasks list
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No tasks match your search'
                              : 'No tasks found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedTypes.length,
                    itemBuilder: (context, index) {
                      final type = sortedTypes[index];
                      final tasks = tasksByType[type]!;

                      return _TaskTypeSection(
                        taskType: type,
                        tasks: tasks,
                        isExpanded: _expandedSections[type] ?? true,
                        onToggleExpand: () {
                          setState(() {
                            _expandedSections[type] = !(_expandedSections[type] ?? true);
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Section widget for each task type
class _TaskTypeSection extends StatelessWidget {
  final TaskType taskType;
  final List<TaskEntity> tasks;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _TaskTypeSection({
    required this.taskType,
    required this.tasks,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type header (clickable)
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      taskType.label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tasks list (collapsible)
          if (isExpanded) ...[
            const Divider(height: 1),
            ...tasks.map((task) => _TaskItem(task: task)),
          ],
        ],
      ),
    );
  }
}

/// Individual task item widget
class _TaskItem extends ConsumerWidget {
  final TaskEntity task;

  const _TaskItem({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateHelper.parseDate(task.currentDate);
    final displayDate = DateHelper.formatDateForDisplay(date);
    final createdDate = DateHelper.parseDate(task.createdDate);
    final displayCreatedDate = DateHelper.formatDateForDisplay(createdDate);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        onTap: () => _showEditTaskBottomSheet(context, ref, task),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: task.isCompleted ? Colors.green : Colors.grey,
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description != null && task.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${task.durationMinutes} min',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        displayDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  if (task.isCarriedOver)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Carried',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.create,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Created on $displayCreatedDate',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getPriorityColor(task.priority).withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            task.priority.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _getPriorityColor(task.priority),
            ),
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.critical:
        return Colors.red;
      case TaskPriority.high:
        return Colors.orange;
      case TaskPriority.medium:
        return Colors.blue;
      case TaskPriority.low:
        return Colors.green;
    }
  }

  void _showEditTaskBottomSheet(BuildContext context, WidgetRef ref, TaskEntity task) {
    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(text: task.description ?? '');
    final notesController = TextEditingController(text: task.notes ?? '');
    final formKey = GlobalKey<FormState>();
    
    // Initialize hours and minutes from existing task duration
    int selectedHours = task.durationMinutes ~/ 60;
    int selectedMinutes = task.durationMinutes % 60;
    
    TaskType selectedType = task.taskType;
    TaskPriority selectedPriority = task.priority;
    bool isPermanent = task.isPermanent;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                key: formKey,
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
                      'Edit Task',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Task title
                    TextFormField(
                      controller: titleController,
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
                      controller: descriptionController,
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
                              setModalState(() {
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
                              setModalState(() {
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
                              setModalState(() {
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
                              setModalState(() {
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
                      controller: notesController,
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
                              setModalState(() {
                                isPermanent = value;
                              });
                            },
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
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
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
                                
                                final notifier = ref.read(taskStateProvider.notifier);
                                
                                notifier.updateTask(task.copyWith(
                                  title: titleController.text.trim(),
                                  description: descriptionController.text.trim().isEmpty 
                                      ? null 
                                      : descriptionController.text.trim(),
                                  durationMinutes: durationMinutes,
                                  taskType: selectedType,
                                  priority: selectedPriority,
                                  notes: notesController.text.trim().isEmpty
                                      ? null
                                      : notesController.text.trim(),
                                  isPermanent: isPermanent,
                                ));
                                
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Task updated!'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Save'),
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
        ),
      ),
    );
  }
}
