import 'dart:async';
import 'dart:convert';

import 'package:android_ssh_codex/src/protocol/codex_remote_api.dart';
import 'package:android_ssh_codex/src/protocol/json_rpc_client.dart';
import 'package:android_ssh_codex/src/protocol/rpc_transport.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingTransport implements RpcTransport {
  final incoming = StreamController<String>();
  final sent = <String>[];

  @override
  Stream<String> get messages => incoming.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async {
    if (!incoming.isClosed) await incoming.close();
  }
}

void main() {
  test('reads exactly one recent 20-item task page', () async {
    final transport = _RecordingTransport();
    final rpc = JsonRpcClient(transport)..start();
    try {
      final page = CodexRemoteApi(rpc).readTaskPage();
      final listRequest =
          jsonDecode(transport.sent.single) as Map<String, dynamic>;
      expect(listRequest, {
        'method': 'thread/list',
        'id': 1,
        'params': {
          'limit': 20,
          'archived': false,
          'sortKey': 'recency_at',
          'sortDirection': 'desc',
        },
      });
      transport.incoming.add(jsonEncode({
        'id': listRequest['id'],
        'result': {
          'data': [],
          'nextCursor': 'next-page',
        },
      }));

      final result = await page;
      await pumpEventQueue();

      expect(result.tasks, isEmpty);
      expect(result.nextCursor, 'next-page');
      expect(transport.sent, hasLength(1));
    } finally {
      await rpc.close();
    }
  });

  test('project continuation adds cwd and the opaque cursor', () async {
    final transport = _RecordingTransport();
    final rpc = JsonRpcClient(transport)..start();
    try {
      final page = CodexRemoteApi(rpc).readTaskPage(
        cwd: '/srv/mobile',
        cursor: 'opaque-cursor',
      );
      final request = jsonDecode(transport.sent.single) as Map<String, dynamic>;

      expect(request['params'], {
        'limit': 20,
        'archived': false,
        'sortKey': 'recency_at',
        'sortDirection': 'desc',
        'cwd': '/srv/mobile',
        'cursor': 'opaque-cursor',
      });
      transport.incoming.add(jsonEncode({
        'id': request['id'],
        'result': {'data': []},
      }));

      await page;
      expect(transport.sent, hasLength(1));
    } finally {
      await rpc.close();
    }
  });

  test('loaded thread list sends an explicit empty params object', () async {
    final transport = _RecordingTransport();
    final rpc = JsonRpcClient(transport)..start();
    try {
      final loaded = CodexRemoteApi(rpc).readLoadedThreadIds();

      final loadedRequest =
          jsonDecode(transport.sent.single) as Map<String, dynamic>;
      transport.incoming.add(jsonEncode({
        'id': loadedRequest['id'],
        'result': {'data': []},
      }));
      await loaded;

      expect(loadedRequest, {
        'method': 'thread/loaded/list',
        'id': 1,
        'params': <String, dynamic>{},
      });
    } finally {
      await rpc.close();
    }
  });

  test('maps a persisted Codex thread to a task snapshot', () {
    final snapshot = CodexRemoteApi.parseThread({
      'id': 'thr_1',
      'name': 'Fix login',
      'cwd': '/srv/app',
      'updatedAt': 1785484800,
      'status': {'type': 'active'},
      'turns': [
        {
          'items': [
            {'id': 'u1', 'type': 'userMessage', 'text': 'Fix login'},
            {'id': 'a1', 'type': 'agentMessage', 'text': 'Inspecting.'},
          ],
        },
      ],
    });

    expect(snapshot.id, 'thr_1');
    expect(snapshot.title, 'Fix login');
    expect(snapshot.status, TaskStatus.running);
    expect(snapshot.items.map((item) => item.kind), [
      TaskItemKind.user,
      TaskItemKind.agent,
    ]);
  });

  test('preserves unknown items as visible activity instead of dropping them',
      () {
    final snapshot = CodexRemoteApi.parseThread({
      'id': 'thr_2',
      'status': {'type': 'idle'},
      'turns': [
        {
          'items': [
            {'id': 'future', 'type': 'newServerItem', 'summary': 'New event'},
          ],
        },
      ],
    });

    expect(snapshot.items.single.kind, TaskItemKind.notice);
    expect(snapshot.items.single.text, contains('New event'));
  });

  test('maps live agent deltas into reducer events with stable event ids', () {
    final mapped = CodexRemoteApi.parseNotification(
      'item/agentMessage/delta',
      {
        'threadId': 'thr_1',
        'itemId': 'a1',
        'delta': 'hello',
        'sequence': 8,
      },
    );
    final reducer = TaskReducer();
    final epoch = reducer.beginConnection();

    reducer.applyEvent(epoch, mapped!);
    reducer.applyEvent(epoch, mapped);

    expect(reducer.state.tasks['thr_1']?.items.single.text, 'hello');
  });

  test('appends repeated identical deltas when the protocol has no sequence',
      () {
    final reducer = TaskReducer();
    final epoch = reducer.beginConnection();
    for (var index = 0; index < 2; index++) {
      reducer.applyEvent(
        epoch,
        CodexRemoteApi.parseNotification(
          'item/agentMessage/delta',
          const {
            'threadId': 'thr_1',
            'turnId': 'turn_1',
            'itemId': 'a1',
            'delta': ' ',
          },
        )!,
      );
    }

    expect(reducer.state.tasks['thr_1']?.items.single.text, '  ');
  });
}
