import 'package:android_ssh_codex/src/app_controller.dart';
import 'package:android_ssh_codex/src/projects/remote_project.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:android_ssh_codex/src/ui/task_view.dart';
import 'package:android_ssh_codex/src/ui/tasks_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TaskRecord task(String id, String title, String cwd) => TaskRecord(
        id: id,
        title: title,
        status: TaskStatus.completed,
        cwd: cwd,
        updatedAt: DateTime.utc(2026, 8, 1),
        items: const [],
        ownership: TaskOwnership.available,
        revision: 0,
      );

  const project = RemoteProject(
    id: 'mobile',
    hostId: 'pi',
    name: 'Mobile',
    cwd: '/srv/mobile',
  );

  testWidgets('projects lead the list and unassigned tasks start collapsed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskListPane(
          model: TaskListPaneModel(
            projects: const [project],
            selectedProjectId: project.id,
            projectTasks: [task('project', 'Project task', project.cwd)],
            unassignedTasks: [task('loose', 'Loose task', '/tmp/scratch')],
            connected: true,
          ),
        ),
      ),
    ));

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Mobile'), findsWidgets);
    expect(find.text('Project task'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Loose task'), findsNothing);

    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();

    expect(find.text('Loose task'), findsOneWidget);
  });

  testWidgets('project paging invokes the explicit load-more callback',
      (tester) async {
    var invoked = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskListPane(
          model: TaskListPaneModel(
            projects: const [project],
            selectedProjectId: project.id,
            projectTasks: [task('project', 'Project task', project.cwd)],
            unassignedTasks: const [],
            connected: true,
            hasMoreProjectTasks: true,
          ),
          onLoadMoreProjectTasks: () => invoked = true,
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('load-more-project')));

    expect(invoked, isTrue);
  });

  testWidgets('task timeline distinguishes loading, failure, and empty history',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TaskTimeline(items: [], loading: true),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No task events yet'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeline(
          items: const [],
          error: 'Could not read task',
          onRetry: () {},
        ),
      ),
    ));
    expect(find.text('Could not read task'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TaskTimeline(items: []),
      ),
    ));
    expect(find.text('No task events yet'), findsOneWidget);
  });

  testWidgets('task timeline follows latest content and exposes jump control',
      (tester) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = List.generate(
      40,
      (index) => TaskItem(
        id: 'message-$index',
        kind: TaskItemKind.agent,
        text: 'Model response $index\n\nSecond line for scrolling.',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TaskTimeline(items: items)),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Model response 39'), findsOneWidget);
    expect(find.textContaining('Model response 0'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jump-to-latest')), findsOneWidget);

    await tester.tap(find.byKey(const Key('jump-to-latest')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Model response 39'), findsOneWidget);
    expect(find.byKey(const Key('jump-to-latest')), findsNothing);
  });

  testWidgets('task command menu exposes stable commands only', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCommandMenu(
          enabled: true,
          onSelected: (_) {},
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Task commands'));
    await tester.pumpAndSettle();

    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('Compact context'), findsOneWidget);
    expect(find.textContaining('Experimental'), findsNothing);
  });

  testWidgets('switching tasks clears the previous composer draft',
      (tester) async {
    final controller = AppController.memory();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskView(
          controller: controller,
          task: task('first', 'First task', '/srv/mobile'),
        ),
      ),
    ));
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'draft for first task';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskView(
          controller: controller,
          task: task('second', 'Second task', '/srv/mobile'),
        ),
      ),
    ));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
}
