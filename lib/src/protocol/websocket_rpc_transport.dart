import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'rpc_transport.dart';

final class WebSocketRpcTransport implements RpcTransport {
  WebSocketRpcTransport._(this._channel);

  final WebSocketChannel _channel;

  static Future<WebSocketRpcTransport> connect(Uri uri) async {
    final channel = IOWebSocketChannel(
      WebSocket.connect(
        uri.toString(),
        compression: CompressionOptions.compressionOff,
      ),
    );
    await channel.ready.timeout(const Duration(seconds: 12));
    return WebSocketRpcTransport._(channel);
  }

  @override
  Stream<String> get messages => _channel.stream.map((message) {
        if (message is String) return message;
        if (message is List<int>) return utf8.decode(message);
        return message.toString();
      });

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close() => _channel.sink.close();
}
