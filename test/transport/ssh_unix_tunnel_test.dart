import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_ssh_codex/src/transport/ssh_unix_tunnel.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retries transient remote Unix socket connection failures', () async {
    var attempts = 0;
    var waits = 0;

    final result = await openUnixChannelWithRetry(
      () async {
        attempts++;
        if (attempts < 3) {
          throw SSHChannelOpenError(2, 'Connection refused');
        }
        return 'connected';
      },
      maxAttempts: 3,
      wait: (_) async {
        waits++;
      },
    );

    expect(result, 'connected');
    expect(attempts, 3);
    expect(waits, 2);
  });

  test('does not retry permanent SSH channel-open failures', () async {
    var attempts = 0;

    await expectLater(
      openUnixChannelWithRetry(
        () async {
          attempts++;
          throw SSHChannelOpenError(1, 'Administratively prohibited');
        },
        maxAttempts: 3,
        wait: (_) async {},
      ),
      throwsA(isA<SSHChannelOpenError>()),
    );

    expect(attempts, 1);
  });

  test('stops retrying after the configured attempt limit', () async {
    var attempts = 0;

    await expectLater(
      openUnixChannelWithRetry(
        () async {
          attempts++;
          throw SSHChannelOpenError(2, 'Connection refused');
        },
        maxAttempts: 3,
        wait: (_) async {},
      ),
      throwsA(isA<SSHChannelOpenError>()),
    );

    expect(attempts, 3);
  });

  test('reports the remote proxy failure before the WebSocket EOF', () async {
    final remote = _FakeProxyChannel();
    final tunnel = await SshUnixTunnel.startWithOpener(
      '/home/codex/.cache/android-ssh-codex/app-server.sock',
      () async => remote,
    );
    addTearDown(tunnel.close);

    final failure = expectLater(
      tunnel.firstFailure,
      throwsA(
        isA<CodexProxyException>()
            .having((error) => error.toString(), 'message', contains('127'))
            .having(
              (error) => error.toString(),
              'diagnostic',
              contains('proxy unavailable'),
            ),
      ),
    );

    final local = await Socket.connect(
      InternetAddress.loopbackIPv4,
      tunnel.localPort,
    );
    addTearDown(local.destroy);
    await remote.opened.future;

    remote.stderrController.add(
      Uint8List.fromList(utf8.encode('proxy unavailable\n')),
    );
    remote.exitCode = 127;
    await remote.stderrController.close();
    await remote.stdoutController.close();
    remote.doneCompleter.complete();

    await failure;
  });
}

final class _FakeProxyChannel implements SshProxyChannel {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final stdinController = StreamController<Uint8List>();
  final doneCompleter = Completer<void>();
  final opened = Completer<void>();

  @override
  Stream<Uint8List> get stdout {
    if (!opened.isCompleted) opened.complete();
    return stdoutController.stream;
  }

  @override
  Stream<Uint8List> get stderr => stderrController.stream;

  @override
  StreamSink<Uint8List> get stdin => stdinController.sink;

  @override
  Future<void> get done => doneCompleter.future;

  @override
  int? exitCode;

  @override
  String? exitSignal;

  @override
  void close() {
    if (!doneCompleter.isCompleted) doneCompleter.complete();
  }
}
