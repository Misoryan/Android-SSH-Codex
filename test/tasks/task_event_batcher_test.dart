import 'package:android_ssh_codex/src/tasks/task_event_batcher.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multiple deltas are delivered in one scheduled batch', () async {
    final batches = <List<TaskEvent>>[];
    final batcher = TaskEventBatcher(
      interval: const Duration(milliseconds: 1),
      onFlush: batches.add,
    );
    addTearDown(batcher.dispose);

    batcher.add(
      const TaskEvent.agentDelta('one', 'message', 'event-1', 'Hello'),
    );
    batcher.add(
      const TaskEvent.agentDelta('one', 'message', 'event-2', ' world'),
    );
    expect(batches, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(batches, hasLength(1));
    expect(batches.single, hasLength(2));
  });

  test('flush preserves pending deltas before a non-stream event', () {
    final batches = <List<TaskEvent>>[];
    final batcher = TaskEventBatcher(
      interval: const Duration(minutes: 1),
      onFlush: batches.add,
    );
    addTearDown(batcher.dispose);

    batcher.add(
      const TaskEvent.agentDelta('one', 'message', 'event-1', 'Hello'),
    );
    batcher.flush();

    expect(batches, hasLength(1));
    expect(batches.single.single.delta, 'Hello');
  });
}
