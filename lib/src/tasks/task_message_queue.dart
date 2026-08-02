import 'task_reducer.dart';

enum TaskMessageRoute { start, steer, queue }

enum TaskMessageDisposition { started, steered, queued }

TaskMessageRoute chooseTaskMessageRoute(
  TaskStatus status, {
  required String? activeTurnId,
}) {
  if (activeTurnId != null) return TaskMessageRoute.steer;
  if (status == TaskStatus.running || status == TaskStatus.queued) {
    return TaskMessageRoute.queue;
  }
  return TaskMessageRoute.start;
}

final class TaskMessageQueue<T> {
  final Map<String, List<T>> _messages = {};

  Set<String> get threadIds => Set.unmodifiable(_messages.keys);

  bool hasPending(String threadId) => _messages[threadId]?.isNotEmpty == true;

  void enqueue(String threadId, T message) {
    _messages.putIfAbsent(threadId, () => <T>[]).add(message);
  }

  T? peek(String threadId) {
    final pending = _messages[threadId];
    return pending == null || pending.isEmpty ? null : pending.first;
  }

  T? take(String threadId) {
    final pending = _messages[threadId];
    if (pending == null || pending.isEmpty) return null;
    final message = pending.removeAt(0);
    if (pending.isEmpty) _messages.remove(threadId);
    return message;
  }

  void clear() => _messages.clear();
}
