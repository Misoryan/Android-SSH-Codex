import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../protocol/codex_remote_api.dart';
import '../tasks/task_reducer.dart';
import 'composer_completion.dart';
import 'widgets/timeline_item.dart';

class TaskView extends StatefulWidget {
  const TaskView({required this.controller, required this.task, super.key});

  final AppController controller;
  final TaskRecord task;

  @override
  State<TaskView> createState() => _TaskViewState();
}

class _TaskViewState extends State<TaskView> {
  final _composer = TextEditingController();
  var _sending = false;
  var _commandBusy = false;
  var _lastCommandSucceeded = true;
  RemoteSkill? _selectedSkill;
  List<RemoteSkill>? _availableSkills;
  List<ComposerCompletion> _completions = const [];
  var _loadingSkills = false;

  @override
  void didUpdateWidget(covariant TaskView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _composer.clear();
      _selectedSkill = null;
      _availableSkills = null;
      _completions = const [];
      _sending = false;
      _commandBusy = false;
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final approvals = widget.controller.approvals
        .where((approval) => approval.threadId == task.id)
        .toList(growable: false);
    return Column(
      children: [
        _TaskHeader(
          controller: widget.controller,
          task: task,
          commandBusy: _commandBusy,
          onCommand: _handleCommand,
        ),
        const Divider(height: 1),
        if (task.ownership == TaskOwnership.external)
          _ExternalTaskBanner(
            busy: _commandBusy,
            onGuide: _guideExternalTask,
            onTakeOver: _takeOverExternalTask,
          ),
        Expanded(
          child: TaskTimeline(
            items: task.items,
            loading: widget.controller.isTaskDetailLoading(task.id),
            error: widget.controller.taskDetailError(task.id),
            onRetry: widget.controller.retrySelectedTaskDetails,
          ),
        ),
        for (final approval in approvals)
          _ApprovalBar(
            approval: approval,
            enabled: widget.controller.isConnected,
            onDecision: (decision) =>
                widget.controller.answerApproval(approval, decision),
          ),
        if (_selectedSkill case final skill?)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: InputChip(
                avatar: const Icon(Icons.auto_awesome, size: 18),
                label: Text('\$${skill.name}'),
                tooltip: skill.description.isEmpty ? null : skill.description,
                onDeleted: _sending
                    ? null
                    : () => setState(() => _selectedSkill = null),
              ),
            ),
          ),
        const Divider(height: 1),
        _Composer(
          controller: _composer,
          enabled: task.canWrite && widget.controller.isConnected && !_sending,
          completions: _completions,
          loadingCompletions: _loadingSkills,
          onChanged: _updateCompletions,
          onCompletion: _selectCompletion,
          onSend: _send,
        ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.controller.sendPrompt(text, skill: _selectedSkill);
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _selectedSkill = null;
        _completions = const [];
      });
    } catch (exception) {
      _showError(exception);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleCommand(TaskCommand command) async {
    switch (command) {
      case TaskCommand.skills:
        await _chooseSkill();
      case TaskCommand.goal:
        await _editGoal();
      case TaskCommand.compact:
        await _compactTask();
      case TaskCommand.interrupt:
        await _runCommand(widget.controller.interruptSelectedTask);
    }
  }

  Future<void> _chooseSkill() async {
    final skills =
        await _runCommand(widget.controller.listSkillsForSelectedTask);
    if (!mounted || skills == null) return;
    _availableSkills = skills;
    final selected = await showDialog<RemoteSkill>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose a skill'),
        content: SizedBox(
          width: 480,
          child: skills.isEmpty
              ? const Text('No enabled skills are available for this project.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: skills.length,
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    return ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: Text('\$${skill.name}'),
                      subtitle: skill.description.isEmpty
                          ? null
                          : Text(skill.description),
                      onTap: () => Navigator.pop(context, skill),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (mounted && selected != null) {
      setState(() => _selectedSkill = selected);
    }
  }

  void _updateCompletions(String _) {
    final cursor = _composer.selection.baseOffset;
    final completions = composerCompletions(
      _composer.text,
      cursor,
      _availableSkills ?? const [],
    );
    setState(() => _completions = completions.take(6).toList(growable: false));
    if (_availableSkills == null &&
        !_loadingSkills &&
        hasActiveSkillCompletion(_composer.text, cursor)) {
      _loadCompletionSkills();
    }
  }

  Future<void> _loadCompletionSkills() async {
    setState(() => _loadingSkills = true);
    try {
      final skills = await widget.controller.listSkillsForSelectedTask();
      if (!mounted) return;
      _availableSkills = skills;
      _updateCompletions(_composer.text);
    } catch (exception) {
      _showError(exception);
    } finally {
      if (mounted) setState(() => _loadingSkills = false);
    }
  }

  Future<void> _selectCompletion(ComposerCompletion completion) async {
    final edit = removeActiveCompletionToken(
      _composer.text,
      _composer.selection.baseOffset,
    );
    _composer.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursor),
    );
    setState(() => _completions = const []);
    if (completion.kind == ComposerCompletionKind.skill) {
      RemoteSkill? skill;
      for (final candidate in _availableSkills ?? const <RemoteSkill>[]) {
        if (r'$' + candidate.name == completion.value) {
          skill = candidate;
          break;
        }
      }
      if (skill != null) setState(() => _selectedSkill = skill);
      return;
    }
    final command = switch (completion.value) {
      '/goal' => TaskCommand.goal,
      '/compact' => TaskCommand.compact,
      '/skills' => TaskCommand.skills,
      '/interrupt' => TaskCommand.interrupt,
      _ => null,
    };
    if (command != null) await _handleCommand(command);
  }

  Future<void> _editGoal() async {
    final current = await _runCommand(widget.controller.readSelectedGoal);
    if (!mounted || !_lastCommandSucceeded) return;
    final objective = TextEditingController(text: current?.objective ?? '');
    final budget = TextEditingController(
      text: current?.tokenBudget?.toString() ?? '',
    );
    final action = await showDialog<_GoalAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Task goal'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: objective,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Objective',
                  hintText: 'What should this task accomplish?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Token budget (optional)',
                ),
              ),
              if (current != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${current.status} · ${current.tokensUsed} tokens · '
                    '${current.timeUsedSeconds}s',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _GoalAction.clear),
              child: const Text('Clear goal'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _GoalAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) {
      objective.dispose();
      budget.dispose();
      return;
    }
    if (action == _GoalAction.clear) {
      await _runCommand(widget.controller.clearSelectedGoal);
    } else {
      final tokenBudget =
          budget.text.trim().isEmpty ? null : int.tryParse(budget.text.trim());
      if (budget.text.trim().isNotEmpty && tokenBudget == null) {
        _showError('Token budget must be a whole number.');
      } else {
        await _runCommand(
          () => widget.controller.setSelectedGoal(
            objective: objective.text,
            tokenBudget: tokenBudget,
          ),
        );
      }
    }
    objective.dispose();
    budget.dispose();
  }

  Future<void> _compactTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compact context?'),
        content: const Text(
          'Codex will summarize older context to make more room in this task.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Compact'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runCommand(widget.controller.compactSelectedTask);
    }
  }

  Future<void> _guideExternalTask() async {
    final guidance = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guide active turn'),
        content: TextField(
          controller: guidance,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Add direction without stopping the other client',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send guidance'),
          ),
        ],
      ),
    );
    final text = guidance.text;
    guidance.dispose();
    if (submitted == true && text.trim().isNotEmpty && mounted) {
      await _runCommand(() => widget.controller.guideExternalTask(text));
    }
  }

  Future<void> _takeOverExternalTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop and take over?'),
        content: const Text(
          'This interrupts the active turn in the other client, then unlocks '
          'this task here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop & take over'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runCommand(widget.controller.takeOverExternalTask);
    }
  }

  Future<T?> _runCommand<T>(Future<T> Function() operation) async {
    if (_commandBusy) return null;
    setState(() {
      _commandBusy = true;
      _lastCommandSucceeded = true;
    });
    try {
      return await operation();
    } catch (exception) {
      _lastCommandSucceeded = false;
      _showError(exception);
      return null;
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

enum _GoalAction { save, clear }

enum TaskCommand { skills, goal, compact, interrupt }

class TaskCommandMenu extends StatelessWidget {
  const TaskCommandMenu({
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final bool enabled;
  final ValueChanged<TaskCommand> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<TaskCommand>(
        enabled: enabled,
        tooltip: 'Task commands',
        onSelected: onSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: TaskCommand.skills,
            child: ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('Skills'),
            ),
          ),
          PopupMenuItem(
            value: TaskCommand.goal,
            child: ListTile(
              leading: Icon(Icons.flag_outlined),
              title: Text('Goal'),
            ),
          ),
          PopupMenuItem(
            value: TaskCommand.compact,
            child: ListTile(
              leading: Icon(Icons.compress),
              title: Text('Compact context'),
            ),
          ),
          PopupMenuItem(
            value: TaskCommand.interrupt,
            child: ListTile(
              leading: Icon(Icons.stop_circle_outlined),
              title: Text('Interrupt turn'),
            ),
          ),
        ],
        icon: const Icon(Icons.more_vert),
      );
}

class TaskTimeline extends StatefulWidget {
  const TaskTimeline({
    required this.items,
    this.loading = false,
    this.error,
    this.onRetry,
    super.key,
  });

  final List<TaskItem> items;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<TaskTimeline> createState() => _TaskTimelineState();
}

class _TaskTimelineState extends State<TaskTimeline> {
  static const _followThreshold = 96.0;

  final _scrollController = ScrollController();
  var _followLatest = true;
  var _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scheduleLatest(animated: false);
  }

  @override
  void didUpdateWidget(covariant TaskTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items ||
        oldWidget.loading != widget.loading ||
        oldWidget.error != widget.error) {
      _scheduleLatest(animated: true);
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final awayFromLatest = _distanceFromLatest > _followThreshold;
    if (awayFromLatest == _showJumpToLatest &&
        _followLatest == !awayFromLatest) {
      return;
    }
    setState(() {
      _showJumpToLatest = awayFromLatest;
      _followLatest = !awayFromLatest;
    });
  }

  double get _distanceFromLatest =>
      _scrollController.position.maxScrollExtent -
      _scrollController.position.pixels;

  void _scheduleLatest({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followLatest || !_scrollController.hasClients) return;
      _scrollToLatest(animated: animated);
    });
  }

  void _scrollToLatest({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    _followLatest = true;
    final latest = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        latest,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 10),
              Text(widget.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.items.isEmpty) {
      return const Center(child: Text('No task events yet'));
    }
    return Stack(
      children: [
        SelectionArea(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
            itemCount: widget.items.length,
            itemBuilder: (_, index) =>
                TimelineItemView(item: widget.items[index]),
          ),
        ),
        if (_showJumpToLatest)
          Positioned(
            right: 16,
            bottom: 14,
            child: FloatingActionButton.small(
              key: const Key('jump-to-latest'),
              tooltip: 'Jump to latest',
              onPressed: _scrollToLatest,
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader({
    required this.controller,
    required this.task,
    required this.commandBusy,
    required this.onCommand,
  });

  final AppController controller;
  final TaskRecord task;
  final bool commandBusy;
  final ValueChanged<TaskCommand> onCommand;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            if (MediaQuery.sizeOf(context).width < 800)
              IconButton(
                tooltip: 'Back to tasks',
                onPressed: controller.clearSelectedTask,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (task.cwd.isNotEmpty)
                    Text(
                      task.cwd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (task.status == TaskStatus.running && task.canWrite)
              IconButton(
                tooltip: 'Interrupt turn',
                onPressed: controller.interruptSelectedTask,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            TaskCommandMenu(
              enabled: controller.isConnected && task.canWrite && !commandBusy,
              onSelected: onCommand,
            ),
          ],
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.completions,
    required this.loadingCompletions,
    required this.onChanged,
    required this.onCompletion,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final List<ComposerCompletion> completions;
  final bool loadingCompletions;
  final ValueChanged<String> onChanged;
  final ValueChanged<ComposerCompletion> onCompletion;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (completions.isNotEmpty || loadingCompletions)
                _CompletionPicker(
                  completions: completions,
                  loading: loadingCompletions,
                  onSelected: onCompletion,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      onChanged: onChanged,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: enabled ? 'Message Codex' : 'Read-only task',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: enabled ? onSend : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _CompletionPicker extends StatelessWidget {
  const _CompletionPicker({
    required this.completions,
    required this.loading,
    required this.onSelected,
  });

  final List<ComposerCompletion> completions;
  final bool loading;
  final ValueChanged<ComposerCompletion> onSelected;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: loading && completions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: completions.length,
                  itemBuilder: (context, index) {
                    final completion = completions[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        completion.kind == ComposerCompletionKind.skill
                            ? Icons.auto_awesome
                            : Icons.keyboard_command_key,
                      ),
                      title: Text(completion.value),
                      subtitle: completion.description.isEmpty
                          ? null
                          : Text(
                              completion.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => onSelected(completion),
                    );
                  },
                ),
        ),
      );
}

class _ExternalTaskBanner extends StatelessWidget {
  const _ExternalTaskBanner({
    required this.busy,
    required this.onGuide,
    required this.onTakeOver,
  });

  final bool busy;
  final VoidCallback onGuide;
  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) => MaterialBanner(
        leading: const Icon(Icons.devices_outlined),
        content: const Text(
          'This turn is active in another Codex client. You can guide it '
          'without changing ownership, or stop it and take control here.',
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : onGuide,
            child: const Text('Guide'),
          ),
          FilledButton.tonal(
            onPressed: busy ? null : onTakeOver,
            child: const Text('Stop & take over'),
          ),
        ],
      );
}

class _ApprovalBar extends StatelessWidget {
  const _ApprovalBar({
    required this.approval,
    required this.enabled,
    required this.onDecision,
  });

  final PendingApproval approval;
  final bool enabled;
  final ValueChanged<String> onDecision;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(approval.title,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                approval.detail,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: enabled ? () => onDecision('decline') : null,
                    child: const Text('Deny'),
                  ),
                  FilledButton(
                    onPressed: enabled ? () => onDecision('accept') : null,
                    child: const Text('Allow once'),
                  ),
                  if (approval.availableDecisions.contains('acceptForSession'))
                    FilledButton.tonal(
                      onPressed:
                          enabled ? () => onDecision('acceptForSession') : null,
                      child: const Text('Allow for session'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}
