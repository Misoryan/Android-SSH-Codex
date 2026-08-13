import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_ssh_codex/src/transport/ssh_tcp_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buffers and flushes the first local request', () async {
    final remote = _FakeTcpForwardChannel();
    final opener = Completer<SshTcpForwardChannel>();
    final tunnel = await SshTcpTunnel.startWithOpener(
      remoteHost: '127.0.0.1',
      remotePort: 38765,
      openForward: () => opener.future,
    );
    addTearDown(tunnel.close);

    final local = await Socket.connect('127.0.0.1', tunnel.localPort);
    addTearDown(local.destroy);
    local.add(utf8.encode('websocket-upgrade'));
    await local.flush();

    final received = remote.input.stream.first;
    opener.complete(remote);
    expect(utf8.decode(await received), 'websocket-upgrade');
    await remote.flushed.future;
    expect(remote.flushCount, 1);
  });
}

final class _FakeTcpForwardChannel implements SshTcpForwardChannel {
  final output = StreamController<List<int>>();
  final input = StreamController<List<int>>();
  final completed = Completer<void>();
  final flushed = Completer<void>();
  var flushCount = 0;

  @override
  Stream<List<int>> get stream => output.stream;

  @override
  StreamSink<List<int>> get sink => input.sink;

  @override
  Future<void> get done => completed.future;

  @override
  Future<void> flush() async {
    flushCount++;
    if (!flushed.isCompleted) flushed.complete();
  }

  @override
  void destroy() {
    if (!completed.isCompleted) completed.complete();
  }
}
