import 'dart:async';

import '../tasks/task_reducer.dart';
import 'json_rpc_client.dart';

final class RemoteTaskBatch {
  const RemoteTaskBatch({required this.tasks, required this.loadedThreadIds});

  final List<TaskSnapshot> tasks;
  final Set<String> loadedThreadIds;
}

final class PendingApproval {
  const PendingApproval({
    required this.requestId,
    required this.method,
    required this.threadId,
    required this.title,
    required this.detail,
    required this.availableDecisions,
  });

  final Object requestId;
  final String method;
  final String threadId;
  final String title;
  final String detail;
  final List<String> availableDecisions;
}

final class CodexRemoteApi {
  CodexRemoteApi(this._rpc);

  final JsonRpcClient _rpc;

  Stream<RpcNotification> get notifications => _rpc.notifications;
  Stream<RpcServerRequest> get serverRequests => _rpc.serverRequests;

  Future<void> initialize() async {
    await _rpc.request('initialize', {
      'clientInfo': {
        'name': 'android_ssh_codex',
        'title': 'Android SSH Codex',
        'version': '0.1.0',
      },
      'capabilities': {
        'experimentalApi': false,
      },
    });
    _rpc.notify('initialized', const {});
  }

  Future<RemoteTaskBatch> readTaskBatch() async {
    final threads = <TaskSnapshot>[];
    String? cursor;
    do {
      final result = _map(await _rpc.request('thread/list', {
        'limit': 100,
        'archived': false,
        if (cursor != null) 'cursor': cursor,
      }));
      final data = result['data'] as List<dynamic>? ?? const [];
      threads.addAll(
        data.map((item) => parseThread(_map(item))),
      );
      cursor = result['nextCursor'] as String?;
    } while (cursor != null && cursor.isNotEmpty);

    final loadedResult = _map(
      await _rpc.request('thread/loaded/list', const {}),
    );
    final rawLoaded = loadedResult['data'] ?? loadedResult['threadIds'];
    final loaded = rawLoaded is List
        ? rawLoaded
            .map((item) => item is Map ? item['id'] : item)
            .whereType<String>()
            .toSet()
        : <String>{};
    return RemoteTaskBatch(tasks: threads, loadedThreadIds: loaded);
  }

  Future<TaskSnapshot> readThread(String threadId) async {
    final result = _map(await _rpc.request('thread/read', {
      'threadId': threadId,
      'includeTurns': true,
    }));
    return parseThread(_map(result['thread']));
  }

  Future<String> startThread({required String cwd}) async {
    final result = _map(await _rpc.request('thread/start', {
      'cwd': cwd,
    }));
    return _map(result['thread'])['id'] as String;
  }

  Future<void> resumeThread(String threadId) async {
    await _rpc.request('thread/resume', {'threadId': threadId});
  }

  Future<void> startTurn(String threadId, String text) async {
    await _rpc.request('turn/start', {
      'threadId': threadId,
      'input': [
        {'type': 'text', 'text': text},
      ],
    });
  }

  Future<void> interruptTurn(String threadId, String turnId) async {
    await _rpc.request('turn/interrupt', {
      'threadId': threadId,
      'turnId': turnId,
    });
  }

  void answerApproval(Object requestId, String decision) {
    _rpc.respond(requestId, {'decision': decision});
  }

  static TaskSnapshot parseThread(Map<String, dynamic> thread) {
    final id = thread['id'] as String? ?? 'unknown';
    final items = <TaskItem>[];
    final turns = thread['turns'] as List<dynamic>? ?? const [];
    for (final rawTurn in turns) {
      final turn = _map(rawTurn);
      for (final rawItem in turn['items'] as List<dynamic>? ?? const []) {
        items.add(_parseItem(_map(rawItem)));
      }
    }
    final title = _firstText(
          thread['name'],
          thread['title'],
          thread['preview'],
          items
              .where((item) => item.kind == TaskItemKind.user)
              .firstOrNull
              ?.text,
        ) ??
        'Task ${id.length > 8 ? id.substring(0, 8) : id}';
    return TaskSnapshot(
      id: id,
      title: title,
      status: _parseStatus(thread['status']),
      cwd: thread['cwd'] as String? ?? '',
      updatedAt: _parseTime(
        thread['updatedAt'] ?? thread['createdAt'] ?? thread['updated_at'],
      ),
      items: List.unmodifiable(items),
    );
  }

  static TaskEvent? parseNotification(
    String method,
    Map<String, dynamic> params,
  ) {
    final threadId = params['threadId'] as String? ??
        _map(params['thread'])['id'] as String?;
    if (threadId == null) return null;
    switch (method) {
      case 'turn/started':
      case 'thread/started':
        return TaskEvent.statusChanged(threadId, TaskStatus.running);
      case 'turn/completed':
        final status = _parseStatus(_map(params['turn'])['status']);
        return TaskEvent.statusChanged(threadId, status);
      case 'item/agentMessage/delta':
        final itemId = params['itemId'] as String? ?? 'agent-message';
        final sequence = params['sequence'] ?? params['deltaIndex'];
        return TaskEvent.agentDelta(
          threadId,
          itemId,
          sequence == null ? null : '$threadId:$itemId:$sequence',
          params['delta'] as String? ?? '',
        );
      case 'item/started':
      case 'item/completed':
        final item = _map(params['item']);
        return TaskEvent.itemChanged(threadId, _parseItem(item));
      default:
        return null;
    }
  }

  static PendingApproval parseApproval(RpcServerRequest request) {
    final params = request.params;
    final command = params['command'];
    final detail = command is List
        ? command.join(' ')
        : _firstText(command, params['reason'], params['cwd']) ??
            request.method;
    final decisions = (params['availableDecisions'] as List<dynamic>?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const ['accept', 'decline'];
    return PendingApproval(
      requestId: request.id,
      method: request.method,
      threadId: params['threadId'] as String? ?? '',
      title: request.method.contains('fileChange')
          ? 'Approve file changes'
          : 'Approve command',
      detail: detail,
      availableDecisions: decisions,
    );
  }
}

TaskItem _parseItem(Map<String, dynamic> item) {
  final type = item['type'] as String? ?? 'unknown';
  final id = item['id'] as String? ?? '$type-${item.hashCode}';
  final text = _extractText(item);
  final kind = switch (type) {
    'userMessage' => TaskItemKind.user,
    'agentMessage' => TaskItemKind.agent,
    'commandExecution' => TaskItemKind.command,
    'fileChange' => TaskItemKind.file,
    'mcpToolCall' || 'dynamicToolCall' => TaskItemKind.tool,
    'reasoning' => TaskItemKind.reasoning,
    _ => TaskItemKind.notice,
  };
  return TaskItem(
    id: id,
    kind: kind,
    text: text.isEmpty ? type : text,
    status: item['status']?.toString(),
  );
}

String _extractText(Map<String, dynamic> item) {
  final direct = _firstText(
    item['text'],
    item['summary'],
    item['command'],
    item['output'],
    item['name'],
  );
  if (direct != null) return direct;
  final content = item['content'];
  if (content is List) {
    return content
        .map((part) => _map(part)['text'])
        .whereType<String>()
        .join('\n');
  }
  return '';
}

TaskStatus _parseStatus(Object? raw) {
  final value = raw is Map ? raw['type'] ?? raw['status'] : raw;
  return switch (value?.toString().toLowerCase()) {
    'active' ||
    'running' ||
    'inprogress' ||
    'in_progress' =>
      TaskStatus.running,
    'queued' || 'pending' => TaskStatus.queued,
    'completed' ||
    'complete' ||
    'idle' ||
    'notloaded' ||
    'not_loaded' =>
      TaskStatus.completed,
    'failed' || 'error' || 'systemerror' => TaskStatus.failed,
    'interrupted' || 'cancelled' || 'canceled' => TaskStatus.interrupted,
    _ => TaskStatus.unknown,
  };
}

DateTime _parseTime(Object? raw) {
  if (raw is num) {
    final milliseconds = raw > 1000000000000 ? raw.toInt() : raw.toInt() * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  if (raw is String) {
    return DateTime.tryParse(raw)?.toUtc() ?? DateTime.now().toUtc();
  }
  return DateTime.now().toUtc();
}

String? _firstText(
  Object? first, [
  Object? second,
  Object? third,
  Object? fourth,
  Object? fifth,
]) {
  for (final value in [first, second, third, fourth, fifth]) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return value.join(' ');
  }
  return null;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
