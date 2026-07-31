import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../protocol/codex_remote_api.dart';
import '../tasks/task_reducer.dart';
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
        _TaskHeader(controller: widget.controller, task: task),
        const Divider(height: 1),
        if (task.ownership == TaskOwnership.external)
          const MaterialBanner(
            leading: Icon(Icons.lock_outline),
            content: Text(
              'Running in another Codex client. Updates are visible here; controls remain read-only.',
            ),
            actions: [SizedBox.shrink()],
          ),
        Expanded(
          child: task.items.isEmpty
              ? const Center(child: Text('No task events yet'))
              : SelectionArea(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    itemCount: task.items.length,
                    itemBuilder: (_, index) =>
                        TimelineItemView(item: task.items[index]),
                  ),
                ),
        ),
        for (final approval in approvals)
          _ApprovalBar(
            approval: approval,
            onDecision: (decision) =>
                widget.controller.answerApproval(approval, decision),
          ),
        const Divider(height: 1),
        _Composer(
          controller: _composer,
          enabled: task.canWrite && widget.controller.isConnected && !_sending,
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
      await widget.controller.sendPrompt(text);
      _composer.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader({required this.controller, required this.task});

  final AppController controller;
  final TaskRecord task;

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
          ],
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
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
        ),
      );
}

class _ApprovalBar extends StatelessWidget {
  const _ApprovalBar({required this.approval, required this.onDecision});

  final PendingApproval approval;
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
                    onPressed: () => onDecision('decline'),
                    child: const Text('Deny'),
                  ),
                  FilledButton(
                    onPressed: () => onDecision('accept'),
                    child: const Text('Allow once'),
                  ),
                  if (approval.availableDecisions.contains('acceptForSession'))
                    FilledButton.tonal(
                      onPressed: () => onDecision('acceptForSession'),
                      child: const Text('Allow for session'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}
