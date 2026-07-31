import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../tasks/task_reducer.dart';
import 'task_view.dart';
import 'widgets/connection_badge.dart';

class TasksWorkspace extends StatelessWidget {
  const TasksWorkspace({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final selected = controller.selectedTask;
    if (!wide && selected != null) {
      return SafeArea(child: TaskView(controller: controller, task: selected));
    }
    final list = _TaskList(controller: controller);
    if (!wide) return SafeArea(child: list);
    return SafeArea(
      child: Row(
        children: [
          SizedBox(width: 360, child: list),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? const _NoTaskSelected()
                : TaskView(controller: controller, task: selected),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatefulWidget {
  const _TaskList({required this.controller});

  final AppController controller;

  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final query = _search.text.trim().toLowerCase();
    final tasks = controller.taskState.tasks.values
        .where((task) =>
            query.isEmpty ||
            task.title.toLowerCase().contains(query) ||
            task.cwd.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tasks', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    ConnectionBadge(phase: controller.connectionPhase),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh tasks',
                onPressed: controller.isConnected ? controller.refreshTasks : null,
                icon: const Icon(Icons.refresh),
              ),
              IconButton.filled(
                tooltip: 'New task',
                onPressed: controller.isConnected ? () => _newTask(context) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search tasks',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !controller.isConnected
              ? const _ConnectPrompt()
              : tasks.isEmpty
                  ? const Center(child: Text('No Codex tasks found'))
                  : RefreshIndicator(
                      onRefresh: controller.refreshTasks,
                      child: ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (_, index) => _TaskRow(
                          task: tasks[index],
                          selected: controller.selectedTaskId == tasks[index].id,
                          onTap: () => controller.selectTask(tasks[index].id),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Future<void> _newTask(BuildContext context) async {
    final cwd = TextEditingController();
    final prompt = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New task'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cwd,
                decoration: const InputDecoration(
                  labelText: 'Remote working directory',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prompt,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Task',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Start'),
          ),
        ],
      ),
    );
    if (accepted == true && cwd.text.trim().isNotEmpty && prompt.text.trim().isNotEmpty) {
      await widget.controller.startNewTask(
        cwd: cwd.text.trim(),
        prompt: prompt.text.trim(),
      );
    }
    cwd.dispose();
    prompt.dispose();
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onTap,
  });

  final TaskRecord task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        selected: selected,
        leading: _StatusIcon(status: task.status),
        title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.cwd.isNotEmpty)
              Text(task.cwd, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (task.ownership == TaskOwnership.external)
              Text(
                'Running in another client',
                style: TextStyle(color: Theme.of(context).colorScheme.secondary),
              ),
          ],
        ),
        trailing: task.ownership == TaskOwnership.external
            ? const Icon(Icons.lock_outline, size: 18)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TaskStatus.running => Theme.of(context).colorScheme.primary,
      TaskStatus.failed => Theme.of(context).colorScheme.error,
      TaskStatus.interrupted => Theme.of(context).colorScheme.secondary,
      _ => Theme.of(context).colorScheme.outline,
    };
    return SizedBox.square(
      dimension: 24,
      child: status == TaskStatus.running
          ? CircularProgressIndicator(strokeWidth: 2.5, color: color)
          : Icon(Icons.circle_outlined, color: color, size: 20),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Connect an SSH host to load its Codex tasks.'),
        ),
      );
}

class _NoTaskSelected extends StatelessWidget {
  const _NoTaskSelected();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40),
            SizedBox(height: 12),
            Text('Select a task'),
          ],
        ),
      );
}
