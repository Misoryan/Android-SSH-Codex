import 'package:android_ssh_codex/src/tasks/task_refresh_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queues another refresh from the same connection', () {
    final lock = TaskRefreshLock<Object>();
    final session = Object();
    final owner = lock.tryAcquire(session, 1)!;

    expect(lock.tryAcquire(session, 1, resetPages: true), isNull);
    expect(owner.takeQueuedResetPages(), isTrue);
    expect(owner.takeQueuedResetPages(), isNull);
  });

  test('a new connection replaces an old refresh owner', () {
    final lock = TaskRefreshLock<Object>();
    final oldOwner = lock.tryAcquire(Object(), 1)!;
    final newOwner = lock.tryAcquire(Object(), 2)!;

    lock.release(oldOwner);

    expect(lock.tryAcquire(newOwner.session, 2), isNull);
    lock.release(newOwner);
    expect(lock.tryAcquire(Object(), 3), isNotNull);
  });
}
