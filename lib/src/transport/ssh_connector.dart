import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../profiles/host_profile.dart';
import '../profiles/profile_store.dart';

final class HostKeyChallenge {
  const HostKeyChallenge({
    required this.label,
    required this.algorithm,
    required this.fingerprint,
    this.previousFingerprint,
  });

  final String label;
  final String algorithm;
  final String fingerprint;
  final String? previousFingerprint;

  bool get isMismatch => previousFingerprint != null;
}

final class HostKeyMismatchException implements Exception {
  const HostKeyMismatchException(this.label, this.expected, this.actual);

  final String label;
  final String expected;
  final String actual;

  @override
  String toString() =>
      'Host key mismatch for $label. Expected $expected but received $actual. '
      'Delete and recreate the host profile to trust a replacement key.';
}

String formatHostKeyFingerprint(List<int> bytes) => 'SHA256:${base64Encode(bytes)}';

typedef HostKeyPrompt = Future<bool> Function(HostKeyChallenge challenge);

final class SshConnection {
  const SshConnection({required this.client, this.jumpClient});

  final SSHClient client;
  final SSHClient? jumpClient;

  Future<void> close() async {
    client.close();
    await client.done.catchError((_) {});
    jumpClient?.close();
    await jumpClient?.done.catchError((_) {});
  }
}

final class SshConnector {
  const SshConnector(this._store);

  final ProfileStore _store;

  Future<SshConnection> connect(
    HostProfile profile,
    HostSecret secret, {
    required HostKeyPrompt prompt,
  }) async {
    SSHClient? jumpClient;
    SSHSocket targetSocket;
    final jump = profile.proxyJump;
    if (jump == null) {
      targetSocket = await SSHSocket.connect(
        profile.hostName,
        profile.port,
        timeout: const Duration(seconds: 15),
      );
    } else {
      final jumpSocket = await SSHSocket.connect(
        jump.hostName,
        jump.port,
        timeout: const Duration(seconds: 15),
      );
      jumpClient = _client(
        socket: jumpSocket,
        profileId: '${profile.id}.jump',
        label: '${profile.label} jump host',
        user: jump.user,
        password: secret.jumpPassword ?? secret.password,
        privateKey: secret.jumpPrivateKey ?? secret.privateKey,
        passphrase: secret.jumpPassphrase ?? secret.passphrase,
        prompt: prompt,
      );
      await jumpClient.authenticated;
      targetSocket =
          await jumpClient.forwardLocal(profile.hostName, profile.port);
    }

    final client = _client(
      socket: targetSocket,
      profileId: profile.id,
      label: profile.label,
      user: profile.user,
      password: secret.password,
      privateKey: secret.privateKey,
      passphrase: secret.passphrase,
      prompt: prompt,
    );
    try {
      await client.authenticated;
      return SshConnection(client: client, jumpClient: jumpClient);
    } catch (_) {
      client.close();
      jumpClient?.close();
      rethrow;
    }
  }

  SSHClient _client({
    required SSHSocket socket,
    required String profileId,
    required String label,
    required String user,
    required String? password,
    required String? privateKey,
    required String? passphrase,
    required HostKeyPrompt prompt,
  }) {
    if (user.trim().isEmpty) {
      throw ArgumentError('SSH user is required for $label');
    }
    final identities = privateKey == null || privateKey.trim().isEmpty
        ? null
        : SSHKeyPair.fromPem(privateKey, passphrase);
    return SSHClient(
      socket,
      username: user,
      identities: identities,
      onPasswordRequest:
          password == null || password.isEmpty ? null : () => password,
      onVerifyHostKey: (algorithm, fingerprintBytes) async {
        final fingerprint = formatHostKeyFingerprint(fingerprintBytes);
        final previous = await _store.readHostFingerprint(profileId);
        if (previous == fingerprint) return true;
        if (previous != null) {
          throw HostKeyMismatchException(label, previous, fingerprint);
        }
        final accepted = await prompt(HostKeyChallenge(
          label: label,
          algorithm: algorithm,
          fingerprint: fingerprint,
        ));
        if (accepted) {
          await _store.writeHostFingerprint(profileId, fingerprint);
        }
        return accepted;
      },
      keepAliveInterval: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 20),
      ident: 'AndroidSSHCodex_0.1',
    );
  }
}
