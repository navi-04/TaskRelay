import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/task_type.dart';
import '../../../core/utils/date_utils.dart';

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
class _TaskItem extends StatelessWidget {
  final TaskEntity task;

  const _TaskItem({required this.task});

  @override
  Widget build(BuildContext context) {
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

  Color _getPriorityColor(priority) {
    switch (priority.toString().split('.').last) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.blue;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
