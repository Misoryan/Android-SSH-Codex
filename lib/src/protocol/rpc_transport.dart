abstract interface class RpcTransport {
  Stream<String> get messages;

  void send(String message);

  Future<void> close();
}

