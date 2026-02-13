import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../providers/task_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/custom_types_provider.dart';
import '../../../data/models/task_entity.dart';
import '../../../data/models/estimation_mode.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/providers.dart';
import 'task_detail_screen.dart';

/// View mode for displaying tasks
enum TaskViewMode {
  all('All'),
  byType('By Type'),
  byPriority('By Priority');
  
  final String label;
  const TaskViewMode(this.label);
}

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
  TaskViewMode _viewMode = TaskViewMode.all;
  final Map<String, bool> _expandedSections = {}; // For type/priority sections
  
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
        toolbarHeight: 70,
        title: Row(
          children: [
            Text(
              isToday ? 'Today\'s Tasks' : 'Tasks',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              displayDate,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: widget.selectedDate != null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Search bar and view mode selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
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
                    const SizedBox(width: 8),
                    // View mode dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<TaskViewMode>(
                        value: _viewMode,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down),
                        borderRadius: BorderRadius.circular(12),
                        items: TaskViewMode.values.map((mode) {
                          return DropdownMenuItem(
                            value: mode,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(mode.label),
                            ),
                          );
                        }).toList(),
                        onChanged: (mode) {
                          if (mode != null) {
                            setState(() {
                              _viewMode = mode;
                            });
                          }
                        },
                      ),
                    ),
                  ],
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
      floatingActionButton: DateHelper.isPast(DateHelper.parseDate(taskState.selectedDate))
          ? null
          : FloatingActionButton.extended(
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
        case EstimationMode.countBased:
          return '$val';
      }
    }

    final progressLabel = mode == EstimationMode.timeBased
        ? 'Time'
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
    
    if (tasks.isEmpty) {
      return EmptyStateWidget(
        icon: completedFilter == true 
            ? Icons.check_circle_outline 
            : Icons.task_alt,
        title: _getEmptyTitle(completedFilter),
        subtitle: _getEmptySubtitle(completedFilter),
      );
    }
    
    // Render based on view mode
    switch (_viewMode) {
      case TaskViewMode.all:
        return _buildAllTasksView(context, tasks);
      case TaskViewMode.byType:
        return _buildByTypeView(context, tasks);
      case TaskViewMode.byPriority:
        return _buildByPriorityView(context, tasks);
    }
  }
  
  Widget _buildAllTasksView(BuildContext context, List<TaskEntity> tasks) {
    // Separate recursive and regular tasks
    final permanentTasks = tasks.where((t) => t.isRecurring).toList();
    final regularTasks = tasks.where((t) => !t.isRecurring).toList();
    
    // Sort: incomplete first, then by priority, then by duration
    final customTypes = ref.watch(customTypesProvider);
    
    void sortTasks(List<TaskEntity> taskList) {
      taskList.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        final aPriority = customTypes.findPriority(a.effectivePriorityId);
        final bPriority = customTypes.findPriority(b.effectivePriorityId);
        final priorityCompare = (aPriority?.sortOrder ?? 99).compareTo(bPriority?.sortOrder ?? 99);
        if (priorityCompare != 0) return priorityCompare;
        return b.durationMinutes.compareTo(a.durationMinutes);
      });
    }
    
    sortTasks(permanentTasks);
    sortTasks(regularTasks);
    
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
            // Section header for recursive tasks
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
                    'RECURSIVE TASKS',
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
            // Recursive task item
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
  
  Widget _buildByTypeView(BuildContext context, List<TaskEntity> tasks) {
    final customTypes = ref.watch(customTypesProvider);
    // Group tasks by type ID
    final Map<String, List<TaskEntity>> tasksByType = {};
    for (final task in tasks) {
      final typeId = task.effectiveTypeId;
      if (!tasksByType.containsKey(typeId)) {
        tasksByType[typeId] = [];
      }
      tasksByType[typeId]!.add(task);
    }
    
    // Sort types by custom label
    final sortedTypeIds = tasksByType.keys.toList()
      ..sort((a, b) => customTypes.taskTypeLabelById(a).compareTo(customTypes.taskTypeLabelById(b)));
    
    // Initialize expanded state
    for (final typeId in sortedTypeIds) {
      _expandedSections.putIfAbsent(typeId, () => true);
    }
    
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.all(12),
      itemCount: sortedTypeIds.length,
      itemBuilder: (context, index) {
        final typeId = sortedTypeIds[index];
        final typeTasks = tasksByType[typeId]!;
        final permanentTasks = typeTasks.where((t) => t.isRecurring).toList();
        final regularTasks = typeTasks.where((t) => !t.isRecurring).toList();
        final isExpanded = _expandedSections[typeId] ?? true;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type header
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedSections[typeId] = !isExpanded;
                  });
                },
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
                          customTypes.taskTypeLabelById(typeId),
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
                          '${typeTasks.length}',
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
                // Recursive tasks in this type
                if (permanentTasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.repeat,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Recursive',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...permanentTasks.map((task) => _buildCompactTaskItem(context, task, showType: false)),
                ],
                // Regular tasks in this type
                if (regularTasks.isNotEmpty) ...[
                  if (permanentTasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.task_alt,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Regular',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...regularTasks.map((task) => _buildCompactTaskItem(context, task, showType: false)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildByPriorityView(BuildContext context, List<TaskEntity> tasks) {
    final customTypes = ref.watch(customTypesProvider);
    // Group tasks by priority ID
    final Map<String, List<TaskEntity>> tasksByPriority = {};
    for (final task in tasks) {
      final prioId = task.effectivePriorityId;
      if (!tasksByPriority.containsKey(prioId)) {
        tasksByPriority[prioId] = [];
      }
      tasksByPriority[prioId]!.add(task);
    }
    
    // Sort priorities by sortOrder from custom types
    final sortedPriorityIds = tasksByPriority.keys.toList()
      ..sort((a, b) {
        final aP = customTypes.findPriority(a);
        final bP = customTypes.findPriority(b);
        return (aP?.sortOrder ?? 99).compareTo(bP?.sortOrder ?? 99);
      });
    
    // Initialize expanded state
    for (final prioId in sortedPriorityIds) {
      _expandedSections.putIfAbsent(prioId, () => true);
    }
    
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.all(12),
      itemCount: sortedPriorityIds.length,
      itemBuilder: (context, index) {
        final prioId = sortedPriorityIds[index];
        final priorityTasks = tasksByPriority[prioId]!;
        final permanentTasks = priorityTasks.where((t) => t.isRecurring).toList();
        final regularTasks = priorityTasks.where((t) => !t.isRecurring).toList();
        final isExpanded = _expandedSections[prioId] ?? true;
        final pColor = customTypes.priorityColorById(prioId);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority header
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedSections[prioId] = !isExpanded;
                  });
                },
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
                          customTypes.priorityLabelById(prioId),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: pColor,
                              ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: pColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${priorityTasks.length}',
                          style: TextStyle(
                            color: pColor,
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
                // Recursive tasks in this priority
                if (permanentTasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.repeat,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Recursive',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...permanentTasks.map((task) => _buildCompactTaskItem(context, task)),
                ],
                // Regular tasks in this priority
                if (regularTasks.isNotEmpty) ...[
                  if (permanentTasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.task_alt,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Regular',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...regularTasks.map((task) => _buildCompactTaskItem(context, task)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildCompactTaskItem(BuildContext context, TaskEntity task, {bool showType = true}) {
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(taskId: task.id),
          ),
        ),
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
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            color: task.isCompleted ? Colors.grey : null,
          ),
        ),
        subtitle: task.description != null && task.description!.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  task.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              )
            : null,
        trailing: Builder(builder: (_) {
          final customTypes = ref.watch(customTypesProvider);
          final pColor = customTypes.priorityColorById(task.effectivePriorityId);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showType)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    customTypes.taskTypeLabelById(task.effectiveTypeId),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (showType) const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: pColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  customTypes.priorityLabelById(task.effectivePriorityId),
                  style: TextStyle(
                    fontSize: 10,
                    color: pColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
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
                        color: ref.watch(customTypesProvider).priorityColorById(task.effectivePriorityId).withOpacity(0.3),
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
                          child: Builder(builder: (_) {
                            final customTypes = ref.watch(customTypesProvider);
                            return _buildChip(
                              customTypes.taskTypeLabelById(task.effectiveTypeId),
                              Colors.purple,
                            );
                          }),
                        ),
                        const SizedBox(width: 6),
                        // Priority (tappable)
                        GestureDetector(
                          onTap: () => _showChangePriorityDialog(context, task),
                          child: Builder(builder: (_) {
                            final customTypes = ref.watch(customTypesProvider);
                            return _buildChip(
                              customTypes.priorityLabelById(task.effectivePriorityId),
                              customTypes.priorityColorById(task.effectivePriorityId),
                            );
                          }),
                        ),
                        const SizedBox(width: 6),
                        // Duration (mode-dependent)
                        if (ref.watch(settingsProvider).estimationMode == EstimationMode.timeBased)
                          _buildChip(
                            task.formattedDuration,
                            AppTheme.info,
                          ),
                        if (task.isCarriedOver) ...[
                          const SizedBox(width: 6),
                          _buildChip(
                            'Carried',
                            Colors.amber,
                          ),
                        ],
                        if (task.isRecurring) ...[
                          const SizedBox(width: 6),
                          _buildChip(
                            'Recursive',
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
    if (task.isRecurring) {
      return _showRecurringDeleteDialog(context, task);
    }
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
  
  Future<bool?> _showRecurringDeleteDialog(BuildContext context, TaskEntity task) async {
    final selectedDate = ref.read(taskStateProvider).selectedDate;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recurring Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How would you like to delete "${task.title}"?'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.today, color: Colors.orange),
              title: const Text('This day only'),
              subtitle: const Text('Task will still appear on other days'),
              onTap: () {
                ref.read(taskStateProvider.notifier).deleteRecurringTaskForDate(task.id, selectedDate);
                Navigator.pop(context, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.update, color: Colors.red),
              title: const Text('This & all upcoming'),
              subtitle: const Text('Task will stop appearing from today onwards'),
              onTap: () {
                ref.read(taskStateProvider.notifier).deleteRecurringTaskFromDate(task.id, selectedDate);
                Navigator.pop(context, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete entirely'),
              subtitle: const Text('Remove this task completely'),
              onTap: () {
                ref.read(taskStateProvider.notifier).deleteTask(task.id);
                Navigator.pop(context, true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  void _showChangeTypeDialog(BuildContext context, TaskEntity task) {
    final customTypes = ref.read(customTypesProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Task Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: customTypes.taskTypes.map((ct) {
            final isSelected = task.effectiveTypeId == ct.id;
            return ListTile(
              title: Text(ct.label),
              trailing: isSelected
                  ? const Icon(Icons.check, color: AppTheme.success)
                  : null,
              onTap: () {
                ref.read(taskStateProvider.notifier).updateTask(
                  task.copyWith(
                    taskType: customTypes.resolveTaskTypeEnum(ct.id),
                    taskTypeId: ct.id,
                  ),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Changed type to ${ct.label}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
  
  void _showChangePriorityDialog(BuildContext context, TaskEntity task) {
    final customTypes = ref.read(customTypesProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Priority'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: customTypes.priorities.map((cp) {
            final isSelected = task.effectivePriorityId == cp.id;
            return ListTile(
              title: Text(cp.label),
              trailing: isSelected
                  ? const Icon(Icons.check, color: AppTheme.success)
                  : null,
              onTap: () {
                ref.read(taskStateProvider.notifier).updateTask(
                  task.copyWith(
                    priority: customTypes.resolvePriorityEnum(cp.id),
                    priorityId: cp.id,
                  ),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Changed priority to ${cp.label}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            );
          }).toList(),
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
  
  void _showAddTaskBottomSheet(BuildContext context) {
    _showTaskFormBottomSheet(context, null);
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
    
    final customTypes = ref.read(customTypesProvider);
    final defaultTypeId = customTypes.taskTypes.isNotEmpty ? customTypes.taskTypes.first.id : 'task';
    final defaultPriorityId = customTypes.priorities.isNotEmpty ? customTypes.priorities.first.id : 'medium';
    String selectedTypeId = (task != null && customTypes.findTaskType(task.effectiveTypeId) != null)
        ? task.effectiveTypeId
        : defaultTypeId;
    String selectedPriorityId = (task != null && customTypes.findPriority(task.effectivePriorityId) != null)
        ? task.effectivePriorityId
        : defaultPriorityId;
    bool isRecurring = task?.isRecurring ?? false;
    String? recurringStartDate = task?.recurringStartDate;
    String? recurringEndDate = task?.recurringEndDate;
    DateTime? alarmTime = task?.alarmTime;
    int reminderTypeIndex = task?.reminderTypeIndex ?? 0;
    
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
                          child: DropdownButtonFormField<String>(
                            value: selectedTypeId,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: ref.read(customTypesProvider).taskTypes.map((ct) {
                              return DropdownMenuItem(
                                value: ct.id,
                                child: Text(ct.label, style: const TextStyle(fontSize: 14)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setModalState(() {
                                selectedTypeId = value!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedPriorityId,
                            decoration: const InputDecoration(
                              labelText: 'Priority',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: ref.read(customTypesProvider).priorities.map((cp) {
                              return DropdownMenuItem(
                                value: cp.id,
                                child: Text(cp.label, style: const TextStyle(fontSize: 14)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setModalState(() {
                                selectedPriorityId = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Duration (mode-dependent)
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
                    ],
                    // Count-based: no duration field
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
                    
                    // Recursive task toggle
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
                      child: Column(
                        children: [
                          Row(
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
                                      'Recursive Task',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Repeats within a date range',
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
                                value: isRecurring,
                                onChanged: (value) {
                                  setModalState(() {
                                    isRecurring = value;
                                    if (value && recurringStartDate == null) {
                                      recurringStartDate = DateHelper.formatDate(DateTime.now());
                                      recurringEndDate = DateHelper.formatDate(DateTime.now().add(const Duration(days: 30)));
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          if (isRecurring) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: recurringStartDate != null ? DateHelper.parseDate(recurringStartDate!) : DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setModalState(() => recurringStartDate = DateHelper.formatDate(picked));
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
                                            recurringStartDate != null
                                                ? DateHelper.formatDateForDisplay(DateHelper.parseDate(recurringStartDate!))
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
                                        initialDate: recurringEndDate != null ? DateHelper.parseDate(recurringEndDate!) : DateTime.now().add(const Duration(days: 30)),
                                        firstDate: recurringStartDate != null ? DateHelper.parseDate(recurringStartDate!) : DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setModalState(() => recurringEndDate = DateHelper.formatDate(picked));
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
                                            recurringEndDate != null
                                                ? DateHelper.formatDateForDisplay(DateHelper.parseDate(recurringEndDate!))
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
                      child: Column(
                        children: [
                          Row(
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
                          // Reminder type toggle — only shown when a time is set
                          if (alarmTime != null) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => reminderTypeIndex = 0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: reminderTypeIndex == 0
                                            ? Colors.orange.withOpacity(0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: reminderTypeIndex == 0
                                              ? Colors.orange
                                              : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.alarm, size: 16,
                                              color: reminderTypeIndex == 0 ? Colors.orange : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600])),
                                          const SizedBox(width: 6),
                                          Text('Alarm',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: reminderTypeIndex == 0 ? FontWeight.w600 : FontWeight.w400,
                                                color: reminderTypeIndex == 0 ? Colors.orange : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),
                                              )),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => reminderTypeIndex = 1),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: reminderTypeIndex == 1
                                            ? Colors.blue.withOpacity(0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: reminderTypeIndex == 1
                                              ? Colors.blue
                                              : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.notifications_outlined, size: 16,
                                              color: reminderTypeIndex == 1 ? Colors.blue : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600])),
                                          const SizedBox(width: 6),
                                          Text('Notification',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: reminderTypeIndex == 1 ? FontWeight.w600 : FontWeight.w400,
                                                color: reminderTypeIndex == 1 ? Colors.blue : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600]),
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

                                // If alarm is set, check overlay permission — strip alarm if denied (only for full alarm type)
                                var effectiveAlarmTime = alarmTime;
                                if (alarmTime != null && reminderTypeIndex == 0) {
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
                                if (isEditing) {
                                  notifier.updateTask(task.copyWith(
                                    title: titleController.text.trim(),
                                    description: descriptionController.text.trim().isEmpty 
                                        ? null 
                                        : descriptionController.text.trim(),
                                    durationMinutes: durationMinutes,
                                    taskType: customTypes.resolveTaskTypeEnum(selectedTypeId),
                                    priority: customTypes.resolvePriorityEnum(selectedPriorityId),
                                    taskTypeId: selectedTypeId,
                                    priorityId: selectedPriorityId,
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                    isRecurring: isRecurring,
                                    recurringStartDate: isRecurring ? recurringStartDate : null,
                                    recurringEndDate: isRecurring ? recurringEndDate : null,
                                    alarmTime: effectiveAlarmTime,
                                    reminderTypeIndex: reminderTypeIndex,
                                  ));
                                } else {
                                  notifier.addTask(
                                    id: const Uuid().v4(),
                                    title: titleController.text.trim(),
                                    description: descriptionController.text.trim().isEmpty 
                                        ? null 
                                        : descriptionController.text.trim(),
                                    durationMinutes: durationMinutes,
                                    taskType: customTypes.resolveTaskTypeEnum(selectedTypeId),
                                    priority: customTypes.resolvePriorityEnum(selectedPriorityId),
                                    taskTypeId: selectedTypeId,
                                    priorityId: selectedPriorityId,
                                    notes: notesController.text.trim().isEmpty
                                        ? null
                                        : notesController.text.trim(),
                                    isRecurring: isRecurring,
                                    recurringStartDate: isRecurring ? recurringStartDate : null,
                                    recurringEndDate: isRecurring ? recurringEndDate : null,
                                    alarmTime: effectiveAlarmTime,
                                    reminderTypeIndex: reminderTypeIndex,
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
