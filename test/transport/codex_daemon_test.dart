import 'dart:convert';

import 'package:android_ssh_codex/src/transport/codex_daemon.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bootstrap passes the exact environment to the SSH command runner',
    () async {
      final environment = Map<String, String>.unmodifiable({
        'LC_CODEX_BACKEND': 'sub2api',
        'CODEX_LABEL': 'mobile client',
      });
      var calls = 0;
      String? receivedCommand;
      Map<String, String>? receivedEnvironment;

      Future<SshCommandResult> runner(
        String command, {
        Map<String, String>? environment,
      }) async {
        calls++;
        receivedCommand = command;
        receivedEnvironment = environment;
        return _result(
          stdout: '/home/codex/.cache/android-ssh-codex/app-server.sock\n',
        );
      }

      final socketPath = await CodexDaemon.bootstrap(
        runner,
        environment: environment,
      );

      expect(calls, 1);
      expect(receivedCommand, CodexDaemon.bootstrapCommand(environment));
      final match = RegExp(
        r"^printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d \| /bin/sh$",
      ).firstMatch(receivedCommand!);
      expect(match, isNotNull);
      final script = utf8.decode(base64Decode(match!.group(1)!));
      expect(script, contains(CodexDaemon.bootstrapScript));
      expect(script, isNot(contains('sub2api')));
      expect(script, isNot(contains('mobile client')));
      expect(identical(receivedEnvironment, environment), isTrue);
      expect(
        socketPath,
        '/home/codex/.cache/android-ssh-codex/app-server.sock',
      );
    },
  );

  test('environment fingerprint is stable and sensitive to map contents', () {
    final first = CodexDaemon.environmentFingerprint(const {
      'Z_LAST': 'last',
      'LC_CODEX_BACKEND': 'sub2api',
    });
    final reordered = CodexDaemon.environmentFingerprint(const {
      'LC_CODEX_BACKEND': 'sub2api',
      'Z_LAST': 'last',
    });
    final changed = CodexDaemon.environmentFingerprint(const {
      'LC_CODEX_BACKEND': 'other',
      'Z_LAST': 'last',
    });

    expect(first, reordered);
    expect(changed, isNot(first));
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('bootstrap omits an empty environment from the SSH request', () async {
    Map<String, String>? receivedEnvironment = const {'unexpected': 'value'};

    await CodexDaemon.bootstrap(
      (command, {environment}) async {
        receivedEnvironment = environment;
        return _result(
          stdout: '/home/codex/.cache/android-ssh-codex/app-server.sock\n',
        );
      },
      environment: const {},
    );

    expect(receivedEnvironment, isNull);
  });

  test('bootstrap reports a nonzero remote exit with stderr', () async {
    await expectLater(
      CodexDaemon.bootstrap(
        (command, {environment}) async => _result(
          stderr: '/bin/sh: codex: not found\n',
          exitCode: 127,
        ),
        environment: const {},
      ),
      throwsA(
        isA<CodexBootstrapException>()
            .having(
              (error) => error.message,
              'message',
              contains('exit code 127'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('codex: not found'),
            ),
      ),
    );
  });

  test('bootstrap reports a remote exit signal', () async {
    await expectLater(
      CodexDaemon.bootstrap(
        (command, {environment}) async => _result(
          stderr: 'terminated remotely',
          exitCode: null,
          exitSignal: 'KILL',
        ),
        environment: const {},
      ),
      throwsA(
        isA<CodexBootstrapException>().having(
          (error) => error.message,
          'message',
          contains('signal KILL'),
        ),
      ),
    );
  });

  test(
    'bootstrap reports diagnostic output when the socket is absent',
    () async {
      await expectLater(
        CodexDaemon.bootstrap(
          (command, {environment}) async => _result(
            stderr: 'socket was not created',
          ),
          environment: const {},
        ),
        throwsA(
          isA<CodexBootstrapException>().having(
            (error) => error.message,
            'message',
            contains('socket was not created'),
          ),
        ),
      );
    },
  );

  test('bootstrap bounds untrusted remote diagnostics', () async {
    Object? thrown;
    try {
      await CodexDaemon.bootstrap(
        (command, {environment}) async => _result(
          stderr: List.filled(5000, 'x').join(),
          exitCode: 1,
        ),
        environment: const {},
      );
    } catch (error) {
      thrown = error;
    }

    expect(thrown, isA<CodexBootstrapException>());
    expect(thrown.toString().length, lessThan(1400));
    expect(thrown.toString(), endsWith('...'));
  });

  test(
    'bootstrap explains server environment rejection without leaking value',
    () async {
      const value = 'top-secret-value';

      await expectLater(
        CodexDaemon.bootstrap(
          (command, {environment}) async {
            throw SSHChannelRequestError(
              'Failed to set environment variable: SECRET_NAME',
            );
          },
          environment: const {'SECRET_NAME': value},
        ),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'message',
                contains('SECRET_NAME'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('AcceptEnv'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains(value)),
              ),
        ),
      );
    },
  );

  test(
    'bootstrap propagates unrelated channel request errors unchanged',
    () async {
      final rejection = SSHChannelRequestError('Failed to execute');

      try {
        await CodexDaemon.bootstrap(
          (command, {environment}) async => throw rejection,
          environment: const {'MODE': 'review'},
        );
        fail('Expected the runner to fail.');
      } catch (error) {
        expect(identical(error, rejection), isTrue);
      }
    },
  );

  test('bootstrap is namespaced and locks daemon lifecycle changes', () {
    const script = CodexDaemon.bootstrapScript;

    expect(script, contains('android-ssh-codex'));
    expect(script, contains(r'mkdir "$lock"'));
    expect(script, contains(r'app-server --listen "unix://$socket"'));
    expect(script, isNot(contains('pkill')));
    expect(script, isNot(contains('killall')));
    expect(script, isNot(contains('.codex/app-server.sock')));
  });

  test(
    'bootstrap restarts only a verified daemon after an environment change',
    () {
      const script = CodexDaemon.bootstrapScript;

      final lockAcquisition = script.indexOf('while ! mkdir');
      final processValidation = script.indexOf('is_our_server_running()');
      final fingerprintCheck =
          script.indexOf('environment_fingerprint_matches');
      final termination = script.indexOf('kill ');

      expect(processValidation, greaterThanOrEqualTo(0));
      expect(fingerprintCheck, greaterThan(processValidation));
      expect(termination, greaterThan(lockAcquisition));
      expect(termination, greaterThan(fingerprintCheck));
      expect(
        script,
        contains('The existing Codex app-server uses a different environment'),
      );
    },
  );

  test(
    'bootstrap persists an environment fingerprint rather than raw values',
    () {
      const script = CodexDaemon.bootstrapScript;

      expect(script, contains('environment-fingerprint'));
      expect(script, contains('environment_fingerprint'));
      expect(script, isNot(contains('LC_CODEX_BACKEND')));
      expect(script, isNot(contains('sub2api')));
    },
  );

  test('bootstrap only removes files below its own base directory', () {
    const script = CodexDaemon.bootstrapScript;

    expect(script, contains(r'rm -f "$socket" "$pidfile"'));
    expect(script, isNot(contains('rm -rf')));
    expect(script, isNot(contains(r'\"')));
  });

  test('bootstrap validates its recorded process before reusing a socket', () {
    const script = CodexDaemon.bootstrapScript;

    expect(script, contains(r'pid=$(cat "$pidfile"'));
    expect(script, contains(r'/proc/$pid/cmdline'));
    expect(script, contains('codex app-server'));
    expect(script, contains(r'rm -f "$socket" "$pidfile"'));
  });

  test('bootstrap never removes socket state before owning the startup lock',
      () {
    const script = CodexDaemon.bootstrapScript;

    final lockAcquisition = script.indexOf(r'while ! mkdir "$lock"');
    final firstCleanup = script.indexOf(r'rm -f "$socket" "$pidfile"');

    expect(lockAcquisition, greaterThanOrEqualTo(0));
    expect(firstCleanup, greaterThan(lockAcquisition));
  });

  test('bootstrap never cleans up a live daemon with a missing socket', () {
    const script = CodexDaemon.bootstrapScript;

    final liveFailure = script.indexOf('App-server process is alive');
    final cleanup = script.indexOf(r'rm -f "$socket" "$pidfile"');

    expect(liveFailure, greaterThanOrEqualTo(0));
    expect(cleanup, greaterThan(liveFailure));
  });
}

SshCommandResult _result({
  String stdout = '',
  String stderr = '',
  int? exitCode = 0,
  String? exitSignal,
}) =>
    SshCommandResult(
      stdout: utf8.encode(stdout),
      stderr: utf8.encode(stderr),
      exitCode: exitCode,
      exitSignal: exitSignal,
    );
