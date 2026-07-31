import 'package:android_ssh_codex/src/ssh_config/ssh_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SshConfig', () {
    test('resolves an alias and fills defaults from Host star', () {
      final config = SshConfig.parse('''
Host work
  HostName dev.internal
  User coder
  Port 2222

Host *
  User fallback
  IdentityFile "~/.ssh/id ed25519"
''');

      final host = config.resolve('work');

      expect(host.hostName, 'dev.internal');
      expect(host.user, 'coder');
      expect(host.port, 2222);
      expect(host.identityFiles, ['~/.ssh/id ed25519']);
    });

    test('uses OpenSSH first obtained value across matching sections', () {
      final config = SshConfig.parse('''
Host *.prod
  User deploy
  Port 2200
Host api.prod
  User root
  HostName 10.0.0.8
''');

      final host = config.resolve('api.prod');

      expect(host.user, 'deploy');
      expect(host.port, 2200);
      expect(host.hostName, '10.0.0.8');
    });

    test('supports negated wildcard patterns', () {
      final config = SshConfig.parse('''
Host *.example !bastion.example
  User service
Host *
  User human
''');

      expect(config.resolve('api.example').user, 'service');
      expect(config.resolve('bastion.example').user, 'human');
    });

    test('resolves one-hop ProxyJump through the same config', () {
      final config = SshConfig.parse('''
Host edge
  HostName edge.example
  User jump
  Port 2201
Host private
  HostName 10.2.0.9
  User codex
  ProxyJump edge
''');

      final host = config.resolve('private');

      expect(host.proxyJump?.alias, 'edge');
      expect(host.proxyJump?.hostName, 'edge.example');
      expect(host.proxyJump?.user, 'jump');
      expect(host.proxyJump?.port, 2201);
    });

    test('reports unsupported multi-hop ProxyJump without guessing', () {
      final config = SshConfig.parse('''
Host private
  HostName 10.2.0.9
  ProxyJump edge,gate
''');

      final host = config.resolve('private');

      expect(host.proxyJump, isNull);
      expect(host.warnings.single, contains('one ProxyJump'));
    });

    test('strips comments outside quotes and preserves hashes in quotes', () {
      final config = SshConfig.parse('''
Host hash
  HostName "box#1.example" # visible comment
''');

      expect(config.resolve('hash').hostName, 'box#1.example');
    });
  });
}

