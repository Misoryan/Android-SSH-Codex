abstract interface class SshTunnel {
  int get localPort;
  Future<void> get firstFailure;
  Future<void> close();
}
