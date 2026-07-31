import 'package:flutter/material.dart';

import '../../tasks/task_reducer.dart';

class TimelineItemView extends StatelessWidget {
  const TimelineItemView({required this.item, super.key});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    final user = item.kind == TaskItemKind.user;
    final agent = item.kind == TaskItemKind.agent;
    final colorScheme = Theme.of(context).colorScheme;
    if (user || agent) {
      return Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: user
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(item.text),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _color(context), width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 18, color: _color(context)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      item.text,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              if (item.status != null) Text(item.status!),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (item.kind) {
        TaskItemKind.command => Icons.terminal,
        TaskItemKind.file => Icons.difference_outlined,
        TaskItemKind.tool => Icons.build_outlined,
        TaskItemKind.reasoning => Icons.psychology_outlined,
        _ => Icons.info_outline,
      };

  String get _label => switch (item.kind) {
        TaskItemKind.command => 'Command',
        TaskItemKind.file => 'File changes',
        TaskItemKind.tool => 'Tool',
        TaskItemKind.reasoning => 'Reasoning',
        _ => 'Activity',
      };

  Color _color(BuildContext context) => switch (item.kind) {
        TaskItemKind.command => Theme.of(context).colorScheme.secondary,
        TaskItemKind.file => Theme.of(context).colorScheme.primary,
        TaskItemKind.tool => Theme.of(context).colorScheme.tertiary,
        _ => Theme.of(context).colorScheme.outline,
      };
}
