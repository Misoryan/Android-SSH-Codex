import 'dart:async';

import 'package:android_ssh_codex/main.dart' as application;
import 'package:android_ssh_codex/src/app.dart';
import 'package:android_ssh_codex/src/app_controller.dart';
import 'package:android_ssh_codex/src/profiles/host_profile.dart';
import 'package:android_ssh_codex/src/profiles/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage failures do not prevent application initialization', () async {
    final controller = AppController(
      store: _ReadProfileStore(
        Future.error(StateError('plugin unavailable')),
      ),
    );

    await controller.initialize();

    expect(controller.profiles, isEmpty);
    expect(controller.error, contains('secure storage'));
  });

  test(
    'application renders before secure storage initialization completes',
    () async {
      final profiles = Completer<List<HostProfile>>();
      AndroidSshCodexApp? renderedApp;
      var initializationCompleted = false;

      final initialization = application.bootstrapApplication(
        _ReadProfileStore(profiles.future),
        (app) => renderedApp = app as AndroidSshCodexApp,
      );
      unawaited(initialization.then((_) => initializationCompleted = true));

      expect(renderedApp, isNotNull);
      expect(initializationCompleted, isFalse);

      profiles.complete(const []);
      await initialization;
      expect(initializationCompleted, isTrue);
    },
  );
}

final class _ReadProfileStore implements ProfileStore {
  const _ReadProfileStore(this.profiles);

  final Future<List<HostProfile>> profiles;

  @override
  Future<List<HostProfile>> readProfiles() => profiles;

  @override
  Future<void> deleteProfile(String id) => throw UnimplementedError();

  @override
  Future<Set<String>> readOwnedThreads(String profileId) =>
      throw UnimplementedError();

  @override
  Future<HostSecret> readSecret(String id) => throw UnimplementedError();

  @override
  Future<String?> readHostFingerprint(String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> writeHostFingerprint(String profileId, String fingerprint) =>
      throw UnimplementedError();

  @override
  Future<void> writeOwnedThreads(String profileId, Set<String> threadIds) =>
      throw UnimplementedError();

  @override
  Future<void> writeProfile(HostProfile profile, HostSecret secret) =>
      throw UnimplementedError();
}
