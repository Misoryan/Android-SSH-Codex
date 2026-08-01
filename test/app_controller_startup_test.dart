import 'dart:async';
import 'dart:io';

import 'package:android_ssh_codex/main.dart' as application;
import 'package:android_ssh_codex/src/app.dart';
import 'package:android_ssh_codex/src/app_controller.dart';
import 'package:android_ssh_codex/src/profiles/host_profile.dart';
import 'package:android_ssh_codex/src/profiles/profile_store.dart';
import 'package:android_ssh_codex/src/transport/codex_daemon.dart';
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

  test(
    'profile bootstrap applies the selected profile environment',
    () async {
      final profile = HostProfile(
        id: 'raspberry-pi',
        label: 'Raspberry Pi',
        hostName: 'pi.example.test',
        user: 'pi',
        port: 22,
        environment: const {
          'LC_CODEX_BACKEND': 'sub2api',
          'CODEX_TOKEN': 'secret-value',
        },
      );
      String? receivedCommand;
      Map<String, String>? receivedEnvironment;

      await bootstrapCodexForProfile(
        (command, {environment}) async {
          receivedCommand = command;
          receivedEnvironment = environment;
          return const [];
        },
        profile,
      );

      expect(
        receivedCommand,
        CodexDaemon.bootstrapCommand(profile.environment),
      );
      expect(identical(receivedEnvironment, profile.environment), isTrue);
    },
  );

  test('connection errors identify the SSH TCP stage and endpoint', () {
    final error = describeConnectionFailure(
      ConnectionStage.ssh,
      const SocketException('Connection refused'),
      const HostProfile(
        id: 'lab',
        label: 'Lab',
        hostName: '192.0.2.10',
        user: 'codex',
        port: 2222,
      ),
    );

    expect(error, contains('SSH'));
    expect(error, contains('192.0.2.10:2222'));
    expect(error, contains('Connection refused'));
  });

  test('connection errors distinguish the local Codex tunnel stage', () {
    final error = describeConnectionFailure(
      ConnectionStage.rpcTunnel,
      const SocketException('Connection refused'),
      const HostProfile(
        id: 'lab',
        label: 'Lab',
        hostName: '192.0.2.10',
        user: 'codex',
        port: 22,
      ),
    );

    expect(error, contains('Codex tunnel'));
    expect(error, contains('SSH connected successfully'));
  });
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
