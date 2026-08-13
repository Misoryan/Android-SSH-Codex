import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ssh_tunnel.dart';

abstract interface class SshTcpForwardChannel {
  Stream<List<int>> get stream;
  StreamSink<List<int>> get sink;
  Future<void> get done;
  Future<void> flush();
  void destroy();
}

typedef SshTcpForwardOpener = Future<SshTcpForwardChannel> Function();

final class _DartSshTcpForwardChannel implements SshTcpForwardChannel {
  const _DartSshTcpForwardChannel(this._channel);

  final SSHForwardChannel _channel;

  @override
  Stream<List<int>> get stream => _channel.stream;

  @override
  StreamSink<List<int>> get sink => _channel.sink;

  @override
  Future<void> get done => _channel.done;

  @override
  Future<void> flush() => _channel.flush();

  @override
  void destroy() => _channel.destroy();
}

final class SshTcpTunnel implements SshTunnel {
  SshTcpTunnel._(
    this.remoteHost,
    this.remotePort,
    this._openForward,
    this._server,
  );

  final String remoteHost;
  final int remotePort;
  final SshTcpForwardOpener _openForward;
  final ServerSocket _server;
  final Set<Socket> _sockets = {};
  final Set<SshTcpForwardChannel> _channels = {};
  final Completer<void> _firstFailure = Completer<void>();
  StreamSubscription<Socket>? _subscription;
  var _closed = false;

  @override
  int get localPort => _server.port;

  @override
  Future<void> get firstFailure => _firstFailure.future;

  static Future<SshTcpTunnel> start(
    SSHClient client, {
    required String remoteHost,
    required int remotePort,
  }) async {
    return startWithOpener(
      remoteHost: remoteHost,
      remotePort: remotePort,
      openForward: () async => _DartSshTcpForwardChannel(
        await client.forwardLocal(remoteHost, remotePort),
      ),
    );
  }

  static Future<SshTcpTunnel> startWithOpener({
    required String remoteHost,
    required int remotePort,
    required SshTcpForwardOpener openForward,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tunnel = SshTcpTunnel._(
      remoteHost,
      remotePort,
      openForward,
      server,
    );
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
    SshTcpForwardChannel? channel;
    final localDone = Completer<void>();
    final firstLocalData = Completer<void>();
    final pendingLocalData = <Uint8List>[];
    final toRemote = socket.listen(
      (chunk) {
        final activeChannel = channel;
        if (activeChannel == null) {
          pendingLocalData.add(Uint8List.fromList(chunk));
          if (!firstLocalData.isCompleted) firstLocalData.complete();
        } else {
          activeChannel.sink.add(chunk);
        }
      },
      onDone: localDone.complete,
      onError: (_, __) => localDone.complete(),
      cancelOnError: true,
    );
    StreamSubscription<List<int>>? toLocal;
    try {
      final hasLocalData = await Future.any<bool>([
        firstLocalData.future.then((_) => true),
        localDone.future.then((_) => false),
      ]);
      if (!hasLocalData || _closed) return;

      channel = await _openForward();
      if (_closed) return;
      _channels.add(channel);

      final remoteDone = Completer<void>();
      toLocal = channel.stream.listen(
        socket.add,
        onDone: remoteDone.complete,
        onError: remoteDone.completeError,
        cancelOnError: true,
      );
      for (final chunk in pendingLocalData) {
        channel.sink.add(chunk);
      }
      pendingLocalData.clear();
      await Future<void>.delayed(Duration.zero);
      await channel.flush();
      unawaited(channel.done.then(
        (_) {
          if (!remoteDone.isCompleted) remoteDone.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!remoteDone.isCompleted) {
            remoteDone.completeError(error, stackTrace);
          }
        },
      ));

      final endedRemotely = await Future.any<bool>([
        localDone.future.then((_) => false),
        remoteDone.future.then((_) => true),
      ]);
      if (endedRemotely) {
        throw StateError(
          'Remote TCP endpoint $remoteHost:$remotePort closed before the '
          'local RPC connection was ready.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Remote Codex TCP tunnel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!_closed && !_firstFailure.isCompleted) {
        _firstFailure.completeError(error, stackTrace);
      }
    } finally {
      await toRemote.cancel();
      await toLocal?.cancel();
      try {
        await channel?.sink.close();
      } catch (_) {
        // The SSH forward may have already closed.
      }
      socket.destroy();
      channel?.destroy();
      _sockets.remove(socket);
      if (channel != null) _channels.remove(channel);
    }
  }

  @override
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
