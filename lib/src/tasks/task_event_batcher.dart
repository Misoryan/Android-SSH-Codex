import 'dart:async';

import 'task_reducer.dart';

final class TaskEventBatcher {
  TaskEventBatcher({
    required this.onFlush,
    this.interval = const Duration(milliseconds: 32),
  });

  final void Function(List<TaskEvent> events) onFlush;
  final Duration interval;
  final List<TaskEvent> _pending = [];
  Timer? _timer;

  void add(TaskEvent event) {
    _pending.add(event);
    _timer ??= Timer(interval, flush);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final events = List<TaskEvent>.unmodifiable(_pending);
    _pending.clear();
    onFlush(events);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void dispose() => clear();
}
