import 'package:flutter/material.dart';

import '../../tasks/task_reducer.dart';
import 'markdown_content.dart';

class TimelineItemView extends StatelessWidget {
  const TimelineItemView({required this.item, super.key});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      TaskItemKind.user || TaskItemKind.agent => _Message(item: item),
      _ => _ActivityCard(item: item),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.item});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    final user = item.kind == TaskItemKind.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: user ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: MarkdownContent(text: item.text),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item});

  final TaskItem item;

  @override
  Widget build(BuildContext context) {
    final expandable = item.kind == TaskItemKind.reasoning ||
        item.detail?.trim().isNotEmpty == true;
    final detail = item.detail?.trim();
    final body =
        item.kind == TaskItemKind.reasoning && detail?.isNotEmpty == true
            ? '${item.text.trim()}\n\n$detail'
            : detail?.isNotEmpty == true
                ? detail!
                : item.text.trim();
    final tile = ExpansionTile(
      leading: Icon(_icon, size: 20, color: _color(context)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.title ?? _label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.status != null) _StatusBadge(status: item.status!),
        ],
      ),
      subtitle: item.kind == TaskItemKind.reasoning || item.text == body
          ? null
          : Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
      initiallyExpanded: !expandable,
      showTrailingIcon: expandable,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: item.kind == TaskItemKind.reasoning
              ? MarkdownContent(text: body)
              : SelectableText(
                  body,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: tile,
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(status, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
