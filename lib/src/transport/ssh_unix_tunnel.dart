import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'codex_daemon.dart';
import 'ssh_tunnel.dart';

abstract interface class SshProxyChannel {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  StreamSink<List<int>> get stdin;
  Future<void> get done;
  int? get exitCode;
  String? get exitSignal;
  void close();
}

typedef SshProxyOpener = Future<SshProxyChannel> Function();

final class CodexProxyException implements Exception {
  const CodexProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _SshSessionProxyChannel implements SshProxyChannel {
  const _SshSessionProxyChannel(this._session);

  final SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  StreamSink<List<int>> get stdin => _session.stdin;

  @override
  Future<void> get done => _session.done;

  @override
  int? get exitCode => _session.exitCode;

  @override
  String? get exitSignal => _session.exitSignal?.signalName;

  @override
  void close() => _session.close();
}

final class SshUnixTunnel implements SshTunnel {
  SshUnixTunnel._(this.remoteSocketPath, this._server, this._openProxy);

  final String remoteSocketPath;
  final ServerSocket _server;
  final SshProxyOpener _openProxy;
  final Set<Socket> _sockets = {};
  final Set<SshProxyChannel> _channels = {};
  final Completer<void> _firstFailure = Completer<void>();
  StreamSubscription<Socket>? _subscription;
  var _closed = false;

  @override
  int get localPort => _server.port;

  @override
  Future<void> get firstFailure => _firstFailure.future;

  static Future<SshUnixTunnel> start(
    SSHClient client,
    String remoteSocketPath, {
    Map<String, String> environment = const {},
  }) =>
      startWithOpener(
        remoteSocketPath,
        () async {
          final session = await client.execute(
            CodexDaemon.proxyCommand(remoteSocketPath),
            environment: environment.isEmpty ? null : environment,
          );
          return _SshSessionProxyChannel(session);
        },
      );

  static Future<SshUnixTunnel> startWithOpener(
    String remoteSocketPath,
    SshProxyOpener openProxy,
  ) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final tunnel = SshUnixTunnel._(remoteSocketPath, server, openProxy);
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
    SshProxyChannel? channel;
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
          activeChannel.stdin.add(chunk);
        }
      },
      onDone: localDone.complete,
      onError: (_, __) => localDone.complete(),
      cancelOnError: true,
    );
    StreamSubscription<Uint8List>? toLocal;
    StreamSubscription<Uint8List>? stderrSubscription;
    try {
      final hasLocalData = await Future.any<bool>([
        firstLocalData.future.then((_) => true),
        localDone.future.then((_) => false),
      ]);
      if (!hasLocalData || _closed) return;

      channel = await _openProxy();
      if (_closed) return;
      _channels.add(channel);

      const diagnosticLimit = 1200;
      final stderr = <int>[];
      final stderrDone = Completer<void>();
      void completeStderr() {
        if (!stderrDone.isCompleted) stderrDone.complete();
      }

      stderrSubscription = channel.stderr.listen(
        (chunk) {
          final remaining = diagnosticLimit - stderr.length;
          if (remaining > 0) stderr.addAll(chunk.take(remaining));
        },
        onDone: completeStderr,
        onError: (_, __) => completeStderr(),
        cancelOnError: true,
      );

      final remoteDone = Completer<void>();
      toLocal = channel.stdout.listen(
        socket.add,
        onDone: remoteDone.complete,
        onError: remoteDone.completeError,
        cancelOnError: true,
      );
      for (final chunk in pendingLocalData) {
        channel.stdin.add(chunk);
      }
      pendingLocalData.clear();
      unawaited(
        channel.done.then(
          (_) {
            if (!remoteDone.isCompleted) remoteDone.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!remoteDone.isCompleted) {
              remoteDone.completeError(error, stackTrace);
            }
          },
        ),
      );

      final endedRemotely = await Future.any<bool>([
        localDone.future.then((_) => false),
        remoteDone.future.then((_) => true),
      ]);
      if (endedRemotely) {
        await channel.done;
        await stderrDone.future;
        throw _proxyClosedException(channel, stderr);
      }
    } catch (error, stackTrace) {
      debugPrint('Remote Codex Unix tunnel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!_closed && !_firstFailure.isCompleted) {
        _firstFailure.completeError(error, stackTrace);
      }
    } finally {
      await toRemote.cancel();
      await toLocal?.cancel();
      await stderrSubscription?.cancel();
      try {
        await channel?.stdin.close();
      } catch (_) {
        // The remote process may have already closed the SSH channel.
      }
      socket.destroy();
      channel?.close();
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
      channel.close();
    }
    _sockets.clear();
    _channels.clear();
  }
}

CodexProxyException _proxyClosedException(
  SshProxyChannel channel,
  List<int> stderr,
) {
  final metadata = <String>[
    if (channel.exitCode != null) 'exit code ${channel.exitCode}',
    if (channel.exitSignal != null) 'signal ${channel.exitSignal}',
  ];
  final diagnostic = utf8.decode(stderr, allowMalformed: true).trim();
  final suffix = <String>[
    if (metadata.isNotEmpty) metadata.join(' and '),
    if (diagnostic.isNotEmpty) diagnostic,
  ];
  return CodexProxyException(
    'Remote Codex proxy closed before the local RPC connection was ready.'
    '${suffix.isEmpty ? '' : ' ${suffix.join(': ')}'}',
  );
}
