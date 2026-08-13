import 'dart:async';
import 'dart:io';

import 'package:android_ssh_codex/src/protocol/websocket_rpc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connects without requesting WebSocket compression', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final extensionHeader = Completer<String?>();
    server.listen((request) async {
      extensionHeader.complete(
        request.headers.value('sec-websocket-extensions'),
      );
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) => socket.add(message));
    });

    final transport = await WebSocketRpcTransport.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/'),
    );
    addTearDown(transport.close);
    expect(await extensionHeader.future, isNull);

    final echoed = transport.messages.first;
    transport.send('{"jsonrpc":"2.0"}');
    expect(await echoed, '{"jsonrpc":"2.0"}');
  });
}
