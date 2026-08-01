import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:android_ssh_codex/src/ui/widgets/markdown_content.dart';
import 'package:android_ssh_codex/src/ui/widgets/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('model replies render selectable Markdown and LaTeX',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MarkdownContent(
          text: '**Result** with `code` and \$x^2 + y^2 = z^2\$',
        ),
      ),
    ));

    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.selectable, isTrue);
    expect(markdown.builders, contains('latex'));
    expect(find.textContaining('Result', findRichText: true), findsOneWidget);
  });

  testWidgets('reasoning is collapsed until explicitly expanded',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TimelineItemView(
          item: TaskItem(
            id: 'reasoning-1',
            kind: TaskItemKind.reasoning,
            title: 'Reasoning',
            text: 'Inspecting the dependency graph',
          ),
        ),
      ),
    ));

    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.text('Inspecting the dependency graph'), findsNothing);

    await tester.tap(find.text('Reasoning'));
    await tester.pumpAndSettle();

    expect(find.text('Inspecting the dependency graph'), findsOneWidget);
  });

  testWidgets('tool card separates identity, status, and verbose detail',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TimelineItemView(
          item: TaskItem(
            id: 'tool-1',
            kind: TaskItemKind.tool,
            title: 'github · create_issue',
            text: 'Create issue',
            detail: '{"repository":"example/repo"}',
            status: 'completed',
          ),
        ),
      ),
    ));

    expect(find.text('github · create_issue'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('{"repository":"example/repo"}'), findsNothing);

    await tester.tap(find.text('github · create_issue'));
    await tester.pumpAndSettle();

    expect(find.text('{"repository":"example/repo"}'), findsOneWidget);
  });
}
