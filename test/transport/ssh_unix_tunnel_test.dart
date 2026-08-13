import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_ssh_codex/src/transport/ssh_unix_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buffers local bytes while the remote proxy channel opens', () async {
    final remote = _FakeProxyChannel();
    final opener = Completer<SshProxyChannel>();
    var openerCalled = false;
    final tunnel = await SshUnixTunnel.startWithOpener(
      '/home/codex/.cache/android-ssh-codex/app-server.sock',
      () {
        openerCalled = true;
        return opener.future;
      },
    );
    addTearDown(tunnel.close);

    final local = await Socket.connect(
      InternetAddress.loopbackIPv4,
      tunnel.localPort,
    );
    addTearDown(local.destroy);
    await Future<void>.delayed(Duration.zero);
    expect(openerCalled, isFalse);

    local.add(utf8.encode('websocket-upgrade'));
    await local.flush();
    await Future<void>.delayed(Duration.zero);
    expect(openerCalled, isTrue);

    final received = remote.stdinController.stream.first;
    opener.complete(remote);

    expect(utf8.decode(await received), 'websocket-upgrade');
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
    local.add(utf8.encode('websocket-upgrade'));
    await local.flush();
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
  final stdinController = StreamController<List<int>>();
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
  StreamSink<List<int>> get stdin => stdinController.sink;

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
