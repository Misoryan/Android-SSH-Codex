import 'package:android_ssh_codex/src/tasks/task_reducer.dart';
import 'package:android_ssh_codex/src/ui/task_timeline_render_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const item = TaskItem(
    id: 'answer',
    kind: TaskItemKind.agent,
    text: 'Long answer',
  );

  test('composer-only rebuilds reuse the existing timeline render', () {
    final items = <TaskItem>[item];
    final cache = TaskTimelineRenderCache<Object>();
    var builds = 0;

    Object build() {
      builds++;
      return Object();
    }

    final first = cache.resolve(
      TaskTimelineRenderState(items: items),
      build,
    );
    final second = cache.resolve(
      TaskTimelineRenderState(items: items),
      build,
    );

    expect(identical(second, first), isTrue);
    expect(builds, 1);
  });

  test('new context or loading state invalidates the timeline render', () {
    final items = <TaskItem>[item];
    final cache = TaskTimelineRenderCache<Object>();
    var builds = 0;

    Object build() {
      builds++;
      return Object();
    }

    final refreshedItems = List<TaskItem>.of(items);
    cache.resolve(TaskTimelineRenderState(items: items), build);
    cache.resolve(
      TaskTimelineRenderState(items: refreshedItems),
      build,
    );
    cache.resolve(
      TaskTimelineRenderState(
        items: refreshedItems,
        loadingOlder: true,
      ),
      build,
    );

    expect(builds, 3);
  });

  test('a new callback owner invalidates the timeline render', () {
    final items = <TaskItem>[item];
    final cache = TaskTimelineRenderCache<Object>();
    final firstOwner = Object();
    final secondOwner = Object();
    var builds = 0;

    Object build() {
      builds++;
      return Object();
    }

    cache.resolve(
      TaskTimelineRenderState(items: items, owner: firstOwner),
      build,
    );
    cache.resolve(
      TaskTimelineRenderState(items: items, owner: secondOwner),
      build,
    );

    expect(builds, 2);
  });
}
