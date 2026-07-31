import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/profiles/profile_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapApplication(SecureProfileStore(), runApp);
}

Future<void> bootstrapApplication(
  ProfileStore store,
  void Function(Widget app) appRunner,
) async {
  final controller = AppController(store: store);
  appRunner(AndroidSshCodexApp(controller: controller));
  await controller.initialize();
}
