import 'package:android_ssh_codex/src/projects/remote_project.dart';
import 'package:android_ssh_codex/src/tasks/task_catalog.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TaskSnapshot snapshot(String id, String cwd) => TaskSnapshot(
        id: id,
        title: 'Task $id',
        status: TaskStatus.completed,
        cwd: cwd,
        updatedAt: DateTime.utc(2026, 8, 1),
        items: const [],
      );

  test(
    'project pages replace then append in server order without duplicates',
    () {
      final catalog = TaskCatalog();

      catalog.replaceProjectPage(
        [snapshot('one', '/repo'), snapshot('two', '/repo')],
        nextCursor: 'page-2',
      );
      catalog.appendProjectPage(
        [snapshot('two', '/repo'), snapshot('three', '/repo')],
        nextCursor: null,
      );

      expect(catalog.projectTaskIds, ['one', 'two', 'three']);
      expect(catalog.projectNextCursor, isNull);
    },
  );

  test(
    'unassigned pages exclude tasks belonging to a normalized project cwd',
    () {
      final catalog = TaskCatalog();
      const projects = [
        RemoteProject(
          id: 'repo',
          hostId: 'pi',
          name: 'Repo',
          cwd: '/srv/repo/',
        ),
      ];

      catalog.replaceUnassignedPage(
        [
          snapshot('project-task', '/srv/repo'),
          snapshot('loose-task', '/tmp/scratch'),
        ],
        projects: projects,
        nextCursor: 'next',
      );

      expect(catalog.unassignedTaskIds, ['loose-task']);
      expect(catalog.unassignedNextCursor, 'next');
    },
  );

  test('unassigned tasks are collapsed until explicitly expanded', () {
    final catalog = TaskCatalog();

    expect(catalog.unassignedExpanded, isFalse);
    catalog.toggleUnassigned();
    expect(catalog.unassignedExpanded, isTrue);
  });

  test('a stale detail completion cannot clear a newer selection', () {
    final state = TaskDetailLoadState();
    final first = state.begin('first');
    final second = state.begin('second');

    state.complete(first);
    expect(state.loadingTaskId, 'second');

    state.fail(second, 'Could not read task');
    expect(state.loadingTaskId, isNull);
    expect(state.taskId, 'second');
    expect(state.error, 'Could not read task');
  });
}
