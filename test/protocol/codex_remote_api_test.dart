import 'package:android_ssh_codex/src/protocol/codex_remote_api.dart';
import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('preserves unknown items as visible activity instead of dropping them', () {
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
}

