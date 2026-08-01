import 'package:android_ssh_codex/src/transport/ssh_unix_tunnel.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retries transient remote Unix socket connection failures', () async {
    var attempts = 0;
    var waits = 0;

    final result = await openUnixChannelWithRetry(
      () async {
        attempts++;
        if (attempts < 3) {
          throw SSHChannelOpenError(2, 'Connection refused');
        }
        return 'connected';
      },
      maxAttempts: 3,
      wait: (_) async {
        waits++;
      },
    );

    expect(result, 'connected');
    expect(attempts, 3);
    expect(waits, 2);
  });

  test('does not retry permanent SSH channel-open failures', () async {
    var attempts = 0;

    await expectLater(
      openUnixChannelWithRetry(
        () async {
          attempts++;
          throw SSHChannelOpenError(1, 'Administratively prohibited');
        },
        maxAttempts: 3,
        wait: (_) async {},
      ),
      throwsA(isA<SSHChannelOpenError>()),
    );

    expect(attempts, 1);
  });

  test('stops retrying after the configured attempt limit', () async {
    var attempts = 0;

    await expectLater(
      openUnixChannelWithRetry(
        () async {
          attempts++;
          throw SSHChannelOpenError(2, 'Connection refused');
        },
        maxAttempts: 3,
        wait: (_) async {},
      ),
      throwsA(isA<SSHChannelOpenError>()),
    );

    expect(attempts, 3);
  });
}
