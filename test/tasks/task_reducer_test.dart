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

