import 'package:android_ssh_codex/src/profiles/host_profile.dart';
import 'package:android_ssh_codex/src/ssh_config/ssh_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a profile from an SSH config alias', () {
    final config = SshConfig.parse('''
Host pi
  HostName 192.0.2.10
  User codex
  Port 2222
  IdentityFile ~/.ssh/pi
''');

    final profile = HostProfile.fromResolved(config.resolve('pi'));

    expect(profile.label, 'pi');
    expect(profile.hostName, '192.0.2.10');
    expect(profile.user, 'codex');
    expect(profile.port, 2222);
    expect(profile.identityFileHint, '~/.ssh/pi');
  });

  test('explicit app values override imported config defaults', () {
    final imported = HostProfile.fromResolved(
      SshConfig.parse('''
Host work
  HostName old.example
  User imported
''').resolve('work'),
    );

    final overridden = imported.copyWith(
      hostName: 'new.example',
      user: 'mobile',
      port: 2200,
    );

    expect(overridden.hostName, 'new.example');
    expect(overridden.user, 'mobile');
    expect(overridden.port, 2200);
  });

  test('round-trips non-secret profile metadata as JSON', () {
    const profile = HostProfile(
      id: 'host-1',
      label: 'Workstation',
      hostName: 'dev.example',
      user: 'coder',
      port: 22,
      authMethod: HostAuthMethod.privateKey,
      identityFileHint: '~/.ssh/id_ed25519',
    );

    expect(HostProfile.fromJson(profile.toJson()), profile);
    expect(profile.toJson().keys, isNot(contains('password')));
    expect(profile.toJson().keys, isNot(contains('privateKey')));
  });
}

