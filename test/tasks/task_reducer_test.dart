import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TaskReducer reducer;

  setUp(() => reducer = TaskReducer());

  TaskSnapshot snapshot(
    String id, {
    TaskStatus status = TaskStatus.completed,
    String text = '',
  }) =>
      TaskSnapshot(
        id: id,
        title: 'Task $id',
        status: status,
        cwd: '/repo',
        updatedAt: DateTime.utc(2026, 7, 31),
        items: text.isEmpty
            ? const []
            : [TaskItem(id: 'message', kind: TaskItemKind.agent, text: text)],
      );

  test('discards a refresh from an older connection epoch', () {
    final firstEpoch = reducer.beginConnection();
    final token = reducer.beginRefresh(firstEpoch);
    reducer.beginConnection();

    reducer.applyRefresh(token, [snapshot('old')], const {});

    expect(reducer.state.tasks, isEmpty);
  });

  test('a new connection does not retain tasks from the previous host', () {
    final firstEpoch = reducer.beginConnection();
    final firstRefresh = reducer.beginRefresh(firstEpoch);
    reducer.applyRefresh(firstRefresh, [snapshot('host-a-task')], const {});

    reducer.beginConnection();

    expect(reducer.state.tasks, isEmpty);
  });

  test('a reconnect can retain stale tasks until its first refresh', () {
    final epoch = reducer.beginConnection();
    final refresh = reducer.beginRefresh(epoch);
    reducer.applyRefresh(refresh, [snapshot('retained')], const {});

    reducer.beginConnection(clearTasks: false);

    expect(reducer.state.tasks.keys, ['retained']);
  });

  test('discards an older overlapping refresh generation', () {
    final epoch = reducer.beginConnection();
    final older = reducer.beginRefresh(epoch);
    final newer = reducer.beginRefresh(epoch);
    reducer.applyRefresh(newer, [snapshot('new')], const {});
    reducer.applyRefresh(older, [snapshot('old')], const {});

    expect(reducer.state.tasks.keys, ['new']);
  });

  test('does not let a late snapshot overwrite a newer live event', () {
    final epoch = reducer.beginConnection();
    final token = reducer.beginRefresh(epoch);
    reducer.applyEvent(
      epoch,
      const TaskEvent.statusChanged('one', TaskStatus.running),
    );

    reducer.applyRefresh(
      token,
      [snapshot('one', status: TaskStatus.completed)],
      const {'one'},
    );

    expect(reducer.state.tasks['one']?.status, TaskStatus.running);
  });

  test('list snapshots with empty turns preserve cached task detail', () {
    final epoch = reducer.beginConnection();
    final detail = reducer.beginRefresh(epoch);
    reducer.applyRefresh(
      detail,
      [snapshot('one', text: 'Full history')],
      const {},
    );

    final listRefresh = reducer.beginRefresh(epoch);
    reducer.applyRefresh(listRefresh, [snapshot('one')], const {});

    expect(reducer.state.tasks['one']?.items.single.text, 'Full history');
  });

  test('marks an active task loaded elsewhere as read-only', () {
    final epoch = reducer.beginConnection();
    final token = reducer.beginRefresh(epoch);

    reducer.applyRefresh(
      token,
      [snapshot('external', status: TaskStatus.running)],
      const {'mine'},
    );

    final task = reducer.state.tasks['external']!;
    expect(task.ownership, TaskOwnership.external);
    expect(task.canWrite, isFalse);
  });

  test('marks an active task loaded by this app-server as interactive', () {
    final epoch = reducer.beginConnection();
    final token = reducer.beginRefresh(epoch);

    reducer.applyRefresh(
      token,
      [snapshot('mine', status: TaskStatus.running)],
      const {'mine'},
    );

    expect(reducer.state.tasks['mine']?.ownership, TaskOwnership.local);
    expect(reducer.state.tasks['mine']?.canWrite, isTrue);
  });

  test('deduplicates streamed deltas by event id', () {
    final epoch = reducer.beginConnection();
    reducer.applyEvent(
      epoch,
      const TaskEvent.agentDelta('one', 'message', 'event-1', 'Hello'),
    );
    reducer.applyEvent(
      epoch,
      const TaskEvent.agentDelta('one', 'message', 'event-1', 'Hello'),
    );

    expect(reducer.state.tasks['one']?.items.single.text, 'Hello');
  });
}
