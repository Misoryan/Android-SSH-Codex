import 'package:flutter/services.dart';

abstract interface class ConnectionService {
  Future<void> start(String hostLabel);

  Future<void> stop();
}

final class NoopConnectionService implements ConnectionService {
  const NoopConnectionService();

  @override
  Future<void> start(String hostLabel) async {}

  @override
  Future<void> stop() async {}
}

final class MethodChannelConnectionService implements ConnectionService {
  const MethodChannelConnectionService();

  static const _channel = MethodChannel(
    'io.github.wkj2333666.android_ssh_codex/connection_service',
  );

  @override
  Future<void> start(String hostLabel) async {
    await _channel.invokeMethod<void>('start', {'hostLabel': hostLabel});
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
