import 'package:android_ssh_codex/src/tasks/task_message_queue.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending messages remain FIFO and isolated per task', () {
    final queue = TaskMessageQueue<String>();

    queue.enqueue('one', 'first');
    queue.enqueue('one', 'second');
    queue.enqueue('two', 'other');

    expect(queue.take('one'), 'first');
    expect(queue.peek('one'), 'second');
    expect(queue.take('two'), 'other');
    expect(queue.take('one'), 'second');
    expect(queue.take('one'), isNull);
  });

  test('clearing the queue removes pending messages for every task', () {
    final queue = TaskMessageQueue<String>();
    queue.enqueue('one', 'first');
    queue.enqueue('two', 'second');

    queue.clear();

    expect(queue.threadIds, isEmpty);
    expect(queue.peek('one'), isNull);
    expect(queue.peek('two'), isNull);
  });

  test('message routing steers active turns and queues an unresolved one', () {
    expect(
      chooseTaskMessageRoute(TaskStatus.running, activeTurnId: 'turn-1'),
      TaskMessageRoute.steer,
    );
    expect(
      chooseTaskMessageRoute(TaskStatus.running, activeTurnId: null),
      TaskMessageRoute.queue,
    );
    expect(
      chooseTaskMessageRoute(TaskStatus.completed, activeTurnId: null),
      TaskMessageRoute.start,
    );
  });
}
