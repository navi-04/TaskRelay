import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../providers/task_provider.dart';
import '../../providers/settings_provider.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/task_type.dart';
import '../../../data/models/task_priority.dart';
import '../../../data/models/estimation_mode.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/providers.dart';
import 'tasks_by_type_screen.dart';
import 'task_detail_screen.dart';

/// Daily Task Screen - Modern design with improved UX
class DailyTaskScreen extends ConsumerStatefulWidget {
  final String? selectedDate;
  
  const DailyTaskScreen({super.key, this.selectedDate});
  
  @override
  ConsumerState<DailyTaskScreen> createState() => _DailyTaskScreenState();
}

class _DailyTaskScreenState extends ConsumerState<DailyTaskScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  TaskPriority? _priorityFilter;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.selectedDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(taskStateProvider.notifier).selectDate(widget.selectedDate!);
      });
    }
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final taskState = ref.watch(taskStateProvider);
    final settings = ref.watch(settingsProvider);
    
    final displayDate = DateHelper.formatDateForDisplay(
      DateHelper.parseDate(taskState.selectedDate),
    );
    final isToday = taskState.selectedDate == DateHelper.formatDate(DateTime.now());
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isToday ? 'Today\'s Tasks' : 'Tasks'),
            Text(
              displayDate,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[400] 
                    : Colors.grey[600],
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: widget.selectedDate != null,
        actions: [
          // View by Type button
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'View by Type',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TasksByTypeScreen(),
                ),
              );
            },
          ),
          // Filter button
          PopupMenuButton<TaskPriority?>(
            icon: Icon(
              _priorityFilter != null ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _priorityFilter != null ? AppTheme.primaryColor : null,
            ),
            tooltip: 'Filter by priority',
            onSelected: (priority) {
              setState(() {
                _priorityFilter = _priorityFilter == priority ? null : priority;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem<TaskPriority?>(
                value: null,
                child: Row(
                  children: [
                    Icon(
                      Icons.clear,
                      color: _priorityFilter == null ? AppTheme.primaryColor : null,
                    ),
                    const SizedBox(width: 8),
                    const Text('All Priorities'),
                  ],
                ),
              ),
              ...TaskPriority.values.map((priority) => PopupMenuItem(
                value: priority,
                child: Row(
                  children: [
                    Text(priority.label),
                    if (_priorityFilter == priority) ...[
                      const Spacer(),
                      const Icon(Icons.check, color: AppTheme.primaryColor, size: 18),
                    ],
                  ],
                ),
              )),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              // Tab bar
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: 'All (${taskState.tasks.length})'),
                  Tab(text: 'Active (${taskState.tasks.length - taskState.completedTasks.length})'),
                  Tab(text: 'Done (${taskState.completedTasks.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: taskState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Progress header
                _buildProgressHeader(context, taskState, settings.dailyTimeLimitMinutes),
                
                // Task list
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTaskList(context, taskState, null),
                      _buildTaskList(context, taskState, false),
                      _buildTaskList(context, taskState, true),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTaskBottomSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }
  
  Widget _buildProgressHeader(BuildContext context, TaskState taskState, int dailyLimitMinutes) {
    final settings = ref.watch(settingsProvider);
    final mode = settings.estimationMode;
    final dailyLimit = settings.effectiveDailyLimit;
    final usedValue = taskState.usedValueFor(mode);
    final isOverLimit = usedValue > dailyLimit;
    final progress = dailyLimit > 0 
        ? (usedValue / dailyLimit).clamp(0.0, 1.0) 
        : 0.0;
    
    // Format value based on mode
    String formatValue(int val) {
      switch (mode) {
        case EstimationMode.timeBased:
          final h = val ~/ 60;
          final m = val % 60;
          if (h > 0 && m > 0) return '${h}h ${m}m';
          if (h > 0) return '${h}h';
          return '${m}m';
        case EstimationMode.weightBased:
          return '$val pts';
        case EstimationMode.countBased:
          return '$val';
      }
    }

    final progressLabel = mode == EstimationMode.timeBased
        ? 'Time'
        : mode == EstimationMode.weightBased
            ? 'Weight'
            : 'Tasks';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$progressLabel: ${formatValue(usedValue)} / ${formatValue(dailyLimit)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isOverLimit ? AppTheme.error : null,
                      ),
                    ),
                    if (taskState.carriedOverTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_forward, size: 12, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              '${taskState.carriedOverTasks.length} carried',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.amber,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
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
    );
  }
  
  Widget _buildTaskList(BuildContext context, TaskState taskState, bool? completedFilter) {
    List<TaskEntity> tasks = taskState.tasks;
    
    // Apply completed filter
    if (completedFilter != null) {
      tasks = tasks.where((t) => t.isCompleted == completedFilter).toList();
    }
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      tasks = tasks.where((t) => 
        t.title.toLowerCase().contains(query) ||
        (t.description?.toLowerCase().contains(query) ?? false) ||
        (t.notes?.toLowerCase().contains(query) ?? false)
      ).toList();
    }
    
    // Apply priority filter
    if (_priorityFilter != null) {
      tasks = tasks.where((t) => t.priority == _priorityFilter).toList();
    }
    
    // Separate permanent and regular tasks
    final permanentTasks = tasks.where((t) => t.isPermanent).toList();
    final regularTasks = tasks.where((t) => !t.isPermanent).toList();
    
    // Sort: incomplete first, then by priority, then by duration
    final priorityOrder = {
      TaskPriority.critical: 0,
      TaskPriority.high: 1,
      TaskPriority.medium: 2,
      TaskPriority.low: 3,
    };
    
    void sortTasks(List<TaskEntity> taskList) {
      taskList.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        final priorityCompare = priorityOrder[a.priority]!.compareTo(priorityOrder[b.priority]!);
        if (priorityCompare != 0) return priorityCompare;
        return b.durationMinutes.compareTo(a.durationMinutes);
      });
    }
    
    sortTasks(permanentTasks);
    sortTasks(regularTasks);
    
    if (tasks.isEmpty) {
      return EmptyStateWidget(
        icon: completedFilter == true 
            ? Icons.check_circle_outline 
            : Icons.task_alt,
        title: _getEmptyTitle(completedFilter),
        subtitle: _getEmptySubtitle(completedFilter),
      );
    }
    
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.all(12),
      itemCount: (permanentTasks.isNotEmpty ? 1 : 0) + permanentTasks.length + 
                 (regularTasks.isNotEmpty && permanentTasks.isNotEmpty ? 1 : 0) + regularTasks.length,
      itemBuilder: (context, index) {
        // Permanent tasks section
        if (permanentTasks.isNotEmpty) {
          if (index == 0) {
            // Section header for permanent tasks
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PERMANENT TASKS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[700]
                          : Colors.grey[300],
                    ),
                  ),
                ],
              ),
            );
          } else if (index <= permanentTasks.length) {
            // Permanent task item
            return AnimatedTaskTile(
              index: index - 1,
              child: _buildTaskCard(context, permanentTasks[index - 1]),
            );
          }
        }
        
        // Regular tasks section
        final regularTasksStartIndex = permanentTasks.isNotEmpty ? permanentTasks.length + 1 : 0;
        
        if (regularTasks.isNotEmpty && permanentTasks.isNotEmpty && index == regularTasksStartIndex) {
          // Section header for regular tasks
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 16),
            child: Row(
              children: [
                Icon(
                  Icons.task_alt,
                  size: 18,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'TODAY\'S TASKS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Colors.grey[300],
                  ),
                ),
              ],
            ),
          );
        } else if (regularTasks.isNotEmpty) {
          // Regular task item
          final taskIndex = index - regularTasksStartIndex - (permanentTasks.isNotEmpty ? 1 : 0);
          if (taskIndex >= 0 && taskIndex < regularTasks.length) {
            return AnimatedTaskTile(
              index: taskIndex,
              child: _buildTaskCard(context, regularTasks[taskIndex]),
            );
          }
        }
        
        return const SizedBox.shrink();
      },
    );
  }
  
  String _getEmptyTitle(bool? completedFilter) {
    if (_searchQuery.isNotEmpty) return 'No matches found';
    if (completedFilter == true) return 'No completed tasks';
    if (completedFilter == false) return 'All caught up!';
    return 'No tasks yet';
  }
  
  String _getEmptySubtitle(bool? completedFilter) {
    if (_searchQuery.isNotEmpty) return 'Try a different search term';
    if (completedFilter == true) return 'Complete some tasks to see them here';
    if (completedFilter == false) return 'All tasks completed!';
    return 'Tap the + button to add your first task';
  }
  
  Widget _buildTaskCard(BuildContext context, TaskEntity task) {
    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) => _confirmDelete(context, task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TaskDetailScreen(taskId: task.id),
              ),
            ),
            borderRadius: BorderRadius.circular(6),
            child: Ink(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(6),
                border: task.isCompleted
                    ? null
                    : Border.all(
                        color: task.priority.color.withOpacity(0.3),
                        width: 1,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: GestureDetector(
                  onTap: () {
                    ref.read(taskStateProvider.notifier).toggleTaskCompletion(task.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: task.isCompleted 
                          ? AppTheme.success 
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: task.isCompleted 
                            ? AppTheme.success 
                            : (Theme.of(context).brightness == Brightness.dark 
                                ? Colors.grey[500]! 
                                : Colors.grey[400]!),
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),
                title: Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: task.isCompleted 
                        ? TextDecoration.lineThrough 
                        : TextDecoration.none,
                    color: task.isCompleted ? Colors.grey : null,
                  ),
                ),
                subtitle: task.description != null && task.description!.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          task.description!,
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.grey[400] 
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showTaskOptions(context, task),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Task Type (tappable)
                        GestureDetector(
                          onTap: () => _showChangeTypeDialog(context, task),
                          child: _buildChip(
                            task.taskType.label,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Priority (tappable)
                        GestureDetector(
                          onTap: () => _showChangePriorityDialog(context, task),
                          child: _buildChip(
                            task.priority.label,
                            task.priority.color,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Duration / Weight (mode-dependent)
                        if (ref.watch(settingsProvider).estimationMode == EstimationMode.timeBased)
                          _buildChip(
                            task.formattedDuration,
                            AppTheme.info,
                          )
                        else if (ref.watch(settingsProvider).estimationMode == EstimationMode.weightBased)
                          _buildChip(
                            task.formattedWeight,
                            AppTheme.info,
                          ),
                        if (task.isCarriedOver) ...[
                          const SizedBox(width: 6),
                          _buildChip(
                            'Carried',
                            Colors.amber,
                          ),
                        ],
                        if (task.isPermanent) ...[
                          const SizedBox(width: 6),
                          _buildChip(
                            'Permanent',
                            AppTheme.primaryColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Created date
                    Row(
                      children: [
                        Icon(
                          Icons.create,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Created on ${DateHelper.formatDateForDisplay(DateHelper.parseDate(task.createdDate))}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<bool?> _confirmDelete(BuildContext context, TaskEntity task) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(taskStateProvider.notifier).deleteTask(task.id);
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  void _showChangeTypeDialog(BuildContext context, TaskEntity task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Task Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TaskType.values.map((type) => ListTile(
            title: Text(type.label),
            trailing: task.taskType == type
                ? const Icon(Icons.check, color: AppTheme.success)
                : null,
            onTap: () {
              ref.read(taskStateProvider.notifier).updateTask(
                task.copyWith(taskType: type),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Changed type to ${type.label}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          )).toList(),
        ),
      ),
    );
  }
  
  void _showChangePriorityDialog(BuildContext context, TaskEntity task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Priority'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TaskPriority.values.map((priority) => ListTile(
            title: Text(priority.label),
            trailing: task.priority == priority
                ? const Icon(Icons.check, color: AppTheme.success)
                : null,
            onTap: () {
              ref.read(taskStateProvider.notifier).updateTask(
                task.copyWith(priority: priority),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Changed priority to ${priority.label}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          )).toList(),
        ),
      ),
    );
  }
  
  void _showTaskOptions(BuildContext context, TaskEntity task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[600] 
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open Task'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskDetailScreen(taskId: task.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                task.isCompleted ? Icons.undo : Icons.check_circle,
                color: task.isCompleted ? null : AppTheme.success,
              ),
              title: Text(task.isCompleted ? 'Mark as Incomplete' : 'Mark as Complete'),
              onTap: () {
                ref.read(taskStateProvider.notifier).toggleTaskCompletion(task.id);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppTheme.error),
              title: const Text('Delete Task', style: TextStyle(color: AppTheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, task);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  void _showTaskDetails(BuildContext context, TaskEntity task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 24),
                  
                  // Title
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: task.isCompleted 
                                ? TextDecoration.lineThrough 
                                : null,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditTaskBottomSheet(context, task);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Tags row - make type and priority editable
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showChangeTypeDialog(context, task);
                        },
                        child: _buildEditableDetailChip(
                          task.taskType.label,
                          Colors.purple,
                          isEditable: true,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showChangePriorityDialog(context, task);
                        },
                        child: _buildEditableDetailChip(
                          task.priority.label,
                          task.priority.color,
                          isEditable: true,
                        ),
                      ),
                      _buildDetailChip('Duration: ${task.formattedDuration}', AppTheme.info),
                      if (task.isCompleted)
                        _buildDetailChip('✓ Completed', AppTheme.success),
                      if (task.isCarriedOver)
                        _buildDetailChip('↪ Carried Over', Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Description
                  if (task.description != null && task.description!.isNotEmpty) ...[
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(task.description!),
                    const SizedBox(height: 24),
                  ],
                  
                  // Notes
                  if (task.notes != null && task.notes!.isNotEmpty) ...[
                    Text(
                      'Notes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[800] 
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(task.notes!),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(taskStateProvider.notifier).toggleTaskCompletion(task.id);
                            Navigator.pop(context);
                          },
                          icon: Icon(task.isCompleted ? Icons.undo : Icons.check),
                          label: Text(task.isCompleted ? 'Mark Incomplete' : 'Complete'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
  
  Widget _buildEditableDetailChip(String label, Color color, {bool isEditable = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (isEditable) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: color),
          ],
        ],
      ),
    );
  }
  
  void _showAddTaskBottomSheet(BuildContext context) {
    _showTaskFormBottomSheet(context, null);
  }
  
  void _showEditTaskBottomSheet(BuildContext context, TaskEntity task) {
    _showTaskFormBottomSheet(context, task);
  }
  
  void _showTaskFormBottomSheet(BuildContext context, TaskEntity? task) {
    final isEditing = task != null;
    final titleController = TextEditingController(text: task?.title ?? '');
    final descriptionController = TextEditingController(text: task?.description ?? '');
    final notesController = TextEditingController(text: task?.notes ?? '');
    final formKey = GlobalKey<FormState>();
    final estimationMode = ref.read(settingsProvider).estimationMode;
    
    // Initialize hours and minutes from existing task duration
    int selectedHours = task != null ? task.durationMinutes ~/ 60 : 0;
    int selectedMinutes = task != null ? task.durationMinutes % 60 : 30;
    
    // Initialize weight
    int selectedWeight = task?.weight ?? 1;
    
    TaskType selectedType = task?.taskType ?? TaskType.task;
    TaskPriority selectedPriority = task?.priority ?? TaskPriority.medium;
    bool isPermanent = task?.isPermanent ?? false;
    DateTime? alarmTime = task?.alarmTime;
    
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
                      isEditing ? 'Edit Task' : 'New Task',
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
                    
                    // Duration / Weight / nothing (mode-dependent)
                    if (estimationMode == EstimationMode.timeBased) ...[
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
                    ] else if (estimationMode == EstimationMode.weightBased) ...[
                      Text(
                        'Weight *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[300] 
                              : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: selectedWeight,
                        decoration: const InputDecoration(
                          labelText: 'Weight',
                          prefixIcon: Icon(Icons.fitness_center),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [1, 2, 3, 5, 8, 10, 13, 15, 20, 25, 30, 40, 50, 75, 100].map((w) {
                          return DropdownMenuItem(
                            value: w,
                            child: Text('$w pt${w != 1 ? 's' : ''}', style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setModalState(() {
                            selectedWeight = value!;
                          });
                        },
                        validator: (value) {
                          if (value == null || value < 1) return 'Weight required';
                          return null;
                        },
                      ),
                    ],
                    // Count-based: no duration/weight field
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
                    const SizedBox(height: 16),
                    
                    // Alarm/Reminder time picker
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.orange.withOpacity(0.1) 
                            : Colors.orange.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.orange.withOpacity(0.3) 
                              : Colors.orange.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.alarm,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reminder',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  alarmTime != null
                                      ? 'Set for ${alarmTime!.hour.toString().padLeft(2, '0')}:${alarmTime!.minute.toString().padLeft(2, '0')}'
                                      : 'No reminder set',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).brightness == Brightness.dark 
                                        ? Colors.grey[400] 
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (alarmTime != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setModalState(() {
                                  alarmTime = null;
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.access_time),
                            onPressed: () async {
                              final selectedDate = DateHelper.parseDate(ref.read(taskStateProvider).selectedDate);
                              final initialTime = alarmTime != null
                                  ? TimeOfDay(hour: alarmTime!.hour, minute: alarmTime!.minute)
                                  : TimeOfDay.now();
                              
                              final TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                              );
                              
                              if (time != null) {
                                setModalState(() {
                                  alarmTime = DateTime(
                                    selectedDate.year,
                                    selectedDate.month,
                                    selectedDate.day,
                                    time.hour,
                                    time.minute,
                                  );
                                });
                              }
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
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                final durationMinutes = estimationMode == EstimationMode.timeBased
                                    ? (selectedHours * 60) + selectedMinutes
                                    : 30; // default fallback
                                
                                // Validate duration (only in time mode)
                                if (estimationMode == EstimationMode.timeBased) {
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
                                }
                                
                                final settings = ref.read(settingsProvider);
                                final notifier = ref.read(taskStateProvider.notifier);
                                
                                // Limit check (time-based only)
                                if (estimationMode == EstimationMode.timeBased) {
                                  String formatTime(int mins) {
                                    final h = mins ~/ 60;
                                    final m = mins % 60;
                                    if (h > 0 && m > 0) return '${h}h ${m}m';
                                    if (h > 0) return '${h}h';
                                    return '${m}m';
                                  }
                                  
                                  if (!isEditing && notifier.wouldExceedLimit(durationMinutes, settings.dailyTimeLimitMinutes)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Adding this task would exceed your daily limit of ${formatTime(settings.dailyTimeLimitMinutes)}',
                                        ),
                                        backgroundColor: AppTheme.warning,
                                      ),
                                    );
                                    return;
                                  }
                                }

                                // If alarm is set, check overlay permission — strip alarm if denied
                                var effectiveAlarmTime = alarmTime;
                                if (alarmTime != null) {
                                  final hasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
                                  if (!hasOverlay) {
                                    await ref.read(notificationServiceProvider).ensureAlarmPermissions(context);
                                    final nowHasOverlay = await ref.read(notificationServiceProvider).hasOverlayPermission();
                                    if (!nowHasOverlay) {
                                      effectiveAlarmTime = null;
                                    }
                                  }
                                }
                                
                                // Auto-sync weight <-> duration across modes
                                final effectiveWeight = estimationMode == EstimationMode.timeBased
                                    ? (durationMinutes / 30).round().clamp(1, 100)
                                    : selectedWeight;
                                final effectiveDuration = estimationMode == EstimationMode.weightBased
                                    ? selectedWeight * 30
                                    : durationMinutes;

                                if (isEditing) {
                                  notifier.updateTask(task.copyWith(
                                    title: titleController.text.trim(),
                                    description: descriptionController.text.trim().isEmpty 
                                        ? null 
                                        : descriptionController.text.trim(),
                                    durationMinutes: effectiveDuration,
                                    taskType: selectedType,
                                    priority: selectedPriority,
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                    isPermanent: isPermanent,
                                    alarmTime: effectiveAlarmTime,
                                    weight: effectiveWeight,
                                  ));
                                } else {
                                  notifier.addTask(
                                    id: const Uuid().v4(),
                                    title: titleController.text.trim(),
                                    description: descriptionController.text.trim().isEmpty 
                                        ? null 
                                        : descriptionController.text.trim(),
                                    durationMinutes: effectiveDuration,
                                    taskType: selectedType,
                                    priority: selectedPriority,
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                    isPermanent: isPermanent,
                                    alarmTime: effectiveAlarmTime,
                                    weight: effectiveWeight,
                                  );
                                }
                                
                                Navigator.pop(context);
                                if (alarmTime != null && effectiveAlarmTime == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${isEditing ? 'Task updated' : 'Task created'} without alarm — "Display over other apps" permission is required for alarms.',
                                      ),
                                      backgroundColor: AppTheme.warning,
                                      duration: const Duration(seconds: 4),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(isEditing ? 'Task updated!' : 'Task added!'),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: Icon(isEditing ? Icons.save : Icons.add),
                            label: Text(isEditing ? 'Save' : 'Add Task'),
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
