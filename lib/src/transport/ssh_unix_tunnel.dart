import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

final class SshUnixTunnel {
  SshUnixTunnel._(this._client, this.remoteSocketPath, this._server);

  final SSHClient _client;
  final String remoteSocketPath;
  final ServerSocket _server;
  final Set<Socket> _sockets = {};
  final Set<SSHForwardChannel> _channels = {};
  StreamSubscription<Socket>? _subscription;
  var _closed = false;

  int get localPort => _server.port;

  static Future<SshUnixTunnel> start(
    SSHClient client,
    String remoteSocketPath,
  ) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tunnel = SshUnixTunnel._(client, remoteSocketPath, server);
    tunnel._subscription = server.listen((socket) {
      unawaited(tunnel._bridge(socket));
    });
    return tunnel;
  }

  Future<void> _bridge(Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    SSHForwardChannel? channel;
    StreamSubscription<List<int>>? toRemote;
    StreamSubscription<List<int>>? toLocal;
    try {
      channel = await _client.forwardLocalUnix(remoteSocketPath);
      _channels.add(channel);
      toRemote = socket.listen(
        channel.sink.add,
        onDone: channel.sink.close,
        onError: (_) => channel?.destroy(),
        cancelOnError: true,
      );
      toLocal = channel.stream.cast<List<int>>().listen(
        socket.add,
        onDone: socket.close,
        onError: (_) => socket.destroy(),
        cancelOnError: true,
      );
      await Future.any([
        toRemote.asFuture<void>(),
        toLocal.asFuture<void>(),
      ]);
    } finally {
      await toRemote?.cancel();
      await toLocal?.cancel();
      socket.destroy();
      channel?.destroy();
      _sockets.remove(socket);
      if (channel != null) _channels.remove(channel);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    for (final channel in _channels.toList()) {
      channel.destroy();
    }
    _sockets.clear();
    _channels.clear();
  }
}
