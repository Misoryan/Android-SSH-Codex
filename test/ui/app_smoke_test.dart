import 'package:android_ssh_codex/src/app.dart';
import 'package:android_ssh_codex/src/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('first launch shows the host workspace and add action', (
    tester,
  ) async {
    final controller = AppController.memory();

    await tester.pumpWidget(AndroidSshCodexApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Hosts'), findsOneWidget);
    expect(find.text('Add host'), findsOneWidget);
    expect(find.text('Remote Codex'), findsOneWidget);
  });

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    testWidgets('workspace has no layout exception at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        AndroidSshCodexApp(controller: AppController.memory()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
