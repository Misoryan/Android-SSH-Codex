import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

const _sshChannelOpenConnectFailed = 2;

Future<T> openUnixChannelWithRetry<T>(
  Future<T> Function() open, {
  int maxAttempts = 50,
  Duration retryDelay = const Duration(milliseconds: 100),
  Future<void> Function(Duration) wait = Future<void>.delayed,
}) async {
  assert(maxAttempts > 0);
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await open();
    } on SSHChannelOpenError catch (error) {
      if (error.code != _sshChannelOpenConnectFailed ||
          attempt == maxAttempts) {
        rethrow;
      }
      await wait(retryDelay);
    }
  }
  throw StateError('Remote Unix socket retry loop ended unexpectedly.');
}

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
      final openedChannel = await openUnixChannelWithRetry<SSHForwardChannel>(
        () => _client.forwardLocalUnix(remoteSocketPath),
      );
      channel = openedChannel;
      _channels.add(openedChannel);
      toRemote = socket.listen(
        openedChannel.sink.add,
        onDone: openedChannel.sink.close,
        onError: (_) => channel?.destroy(),
        cancelOnError: true,
      );
      toLocal = openedChannel.stream.cast<List<int>>().listen(
            socket.add,
            onDone: socket.close,
            onError: (_) => socket.destroy(),
            cancelOnError: true,
          );
      await Future.any([
        toRemote.asFuture<void>(),
        toLocal.asFuture<void>(),
      ]);
    } catch (error, stackTrace) {
      debugPrint('Remote Codex Unix tunnel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
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
