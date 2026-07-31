import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/profiles/profile_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(store: SecureProfileStore());
  await controller.initialize();
  runApp(AndroidSshCodexApp(controller: controller));
}
