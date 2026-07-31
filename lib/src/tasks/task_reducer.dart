enum TaskStatus { unknown, queued, running, completed, failed, interrupted }

enum TaskOwnership { available, local, external }

enum TaskItemKind { user, agent, command, file, tool, reasoning, notice }

final class TaskItem {
  const TaskItem({
    required this.id,
    required this.kind,
    required this.text,
    this.status,
  });

  final String id;
  final TaskItemKind kind;
  final String text;
  final String? status;

  TaskItem copyWith({String? text, String? status}) => TaskItem(
        id: id,
        kind: kind,
        text: text ?? this.text,
        status: status ?? this.status,
      );
}

final class TaskSnapshot {
  const TaskSnapshot({
    required this.id,
    required this.title,
    required this.status,
    required this.cwd,
    required this.updatedAt,
    required this.items,
  });

  final String id;
  final String title;
  final TaskStatus status;
  final String cwd;
  final DateTime updatedAt;
  final List<TaskItem> items;
}

final class TaskRecord {
  const TaskRecord({
    required this.id,
    required this.title,
    required this.status,
    required this.cwd,
    required this.updatedAt,
    required this.items,
    required this.ownership,
    required this.revision,
  });

  factory TaskRecord.placeholder(String id, int revision) => TaskRecord(
        id: id,
        title: 'Task $id',
        status: TaskStatus.unknown,
        cwd: '',
        updatedAt: DateTime.now().toUtc(),
        items: const [],
        ownership: TaskOwnership.available,
        revision: revision,
      );

  final String id;
  final String title;
  final TaskStatus status;
  final String cwd;
  final DateTime updatedAt;
  final List<TaskItem> items;
  final TaskOwnership ownership;
  final int revision;

  bool get canWrite => ownership != TaskOwnership.external;

  TaskRecord copyWith({
    String? title,
    TaskStatus? status,
    String? cwd,
    DateTime? updatedAt,
    List<TaskItem>? items,
    TaskOwnership? ownership,
    int? revision,
  }) =>
      TaskRecord(
        id: id,
        title: title ?? this.title,
        status: status ?? this.status,
        cwd: cwd ?? this.cwd,
        updatedAt: updatedAt ?? this.updatedAt,
        items: items ?? this.items,
        ownership: ownership ?? this.ownership,
        revision: revision ?? this.revision,
      );
}

final class TaskState {
  const TaskState({
    required this.epoch,
    required this.refreshGeneration,
    required this.eventRevision,
    required this.tasks,
  });

  factory TaskState.initial() => const TaskState(
        epoch: 0,
        refreshGeneration: 0,
        eventRevision: 0,
        tasks: {},
      );

  final int epoch;
  final int refreshGeneration;
  final int eventRevision;
  final Map<String, TaskRecord> tasks;
}

final class RefreshToken {
  const RefreshToken(this.epoch, this.generation, this.eventRevision);

  final int epoch;
  final int generation;
  final int eventRevision;
}

enum _TaskEventType { status, agentDelta, item }

final class TaskEvent {
  const TaskEvent.statusChanged(this.taskId, this.status)
      : _type = _TaskEventType.status,
        itemId = null,
        eventId = null,
        delta = null,
        item = null;

  const TaskEvent.agentDelta(
    this.taskId,
    this.itemId,
    this.eventId,
    this.delta,
  )   : _type = _TaskEventType.agentDelta,
        item = null,
        status = null;

  const TaskEvent.itemChanged(this.taskId, this.item)
      : _type = _TaskEventType.item,
        itemId = null,
        eventId = null,
        delta = null,
        status = null;

  final String taskId;
  final _TaskEventType _type;
  final TaskStatus? status;
  final String? itemId;
  final String? eventId;
  final String? delta;
  final TaskItem? item;
}

final class TaskReducer {
  TaskState _state = TaskState.initial();
  final Map<String, Set<String>> _seenEvents = {};

  TaskState get state => _state;

  int beginConnection() {
    _state = TaskState(
      epoch: _state.epoch + 1,
      refreshGeneration: 0,
      eventRevision: _state.eventRevision,
      tasks: _state.tasks,
    );
    return _state.epoch;
  }

  RefreshToken beginRefresh(int epoch) {
    if (epoch != _state.epoch) {
      return RefreshToken(epoch, -1, _state.eventRevision);
    }
    _state = TaskState(
      epoch: _state.epoch,
      refreshGeneration: _state.refreshGeneration + 1,
      eventRevision: _state.eventRevision,
      tasks: _state.tasks,
    );
    return RefreshToken(
      epoch,
      _state.refreshGeneration,
      _state.eventRevision,
    );
  }

  void applyRefresh(
    RefreshToken token,
    List<TaskSnapshot> snapshots,
    Set<String> loadedByUs,
  ) {
    if (token.epoch != _state.epoch ||
        token.generation != _state.refreshGeneration) {
      return;
    }

    final next = <String, TaskRecord>{};
    for (final snapshot in snapshots) {
      final current = _state.tasks[snapshot.id];
      final changedDuringRefresh =
          current != null && current.revision > token.eventRevision;
      final effectiveStatus =
          changedDuringRefresh ? current.status : snapshot.status;
      final ownership = _ownershipFor(effectiveStatus, loadedByUs, snapshot.id);
      next[snapshot.id] = TaskRecord(
        id: snapshot.id,
        title: snapshot.title,
        status: effectiveStatus,
        cwd: snapshot.cwd,
        updatedAt:
            changedDuringRefresh ? current.updatedAt : snapshot.updatedAt,
        items: changedDuringRefresh ? current.items : snapshot.items,
        ownership: ownership,
        revision: current?.revision ?? token.eventRevision,
      );
    }

    for (final entry in _state.tasks.entries) {
      if (!next.containsKey(entry.key) &&
          entry.value.revision > token.eventRevision) {
        next[entry.key] = entry.value;
      }
    }
    _state = TaskState(
      epoch: _state.epoch,
      refreshGeneration: _state.refreshGeneration,
      eventRevision: _state.eventRevision,
      tasks: Map.unmodifiable(next),
    );
  }

  void applyEvent(int epoch, TaskEvent event) {
    if (epoch != _state.epoch) return;
    final revision = _state.eventRevision + 1;
    var current = _state.tasks[event.taskId] ??
        TaskRecord.placeholder(event.taskId, revision);

    switch (event._type) {
      case _TaskEventType.status:
        current = current.copyWith(
          status: event.status,
          updatedAt: DateTime.now().toUtc(),
          revision: revision,
        );
        break;
      case _TaskEventType.agentDelta:
        final seen = _seenEvents.putIfAbsent(event.taskId, () => <String>{});
        if (!seen.add(event.eventId!)) return;
        final items = current.items.toList();
        final index = items.indexWhere((item) => item.id == event.itemId);
        if (index == -1) {
          items.add(TaskItem(
            id: event.itemId!,
            kind: TaskItemKind.agent,
            text: event.delta!,
          ));
        } else {
          items[index] = items[index].copyWith(
            text: '${items[index].text}${event.delta}',
          );
        }
        current = current.copyWith(
          items: List.unmodifiable(items),
          revision: revision,
        );
        break;
      case _TaskEventType.item:
        final items = current.items.toList();
        final index = items.indexWhere((item) => item.id == event.item!.id);
        if (index == -1) {
          items.add(event.item!);
        } else {
          items[index] = event.item!;
        }
        current = current.copyWith(
          items: List.unmodifiable(items),
          revision: revision,
        );
        break;
    }

    final tasks = Map<String, TaskRecord>.of(_state.tasks)
      ..[event.taskId] = current;
    _state = TaskState(
      epoch: _state.epoch,
      refreshGeneration: _state.refreshGeneration,
      eventRevision: revision,
      tasks: Map.unmodifiable(tasks),
    );
  }
}

TaskOwnership _ownershipFor(
  TaskStatus status,
  Set<String> loadedByUs,
  String taskId,
) {
  final active = status == TaskStatus.running || status == TaskStatus.queued;
  if (!active) return TaskOwnership.available;
  return loadedByUs.contains(taskId)
      ? TaskOwnership.local
      : TaskOwnership.external;
}
