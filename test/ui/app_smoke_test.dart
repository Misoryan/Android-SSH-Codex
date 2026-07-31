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
}
