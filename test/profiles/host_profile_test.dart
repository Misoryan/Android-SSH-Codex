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
  SetEnv LC_CODEX_BACKEND=sub2api CODEX_LABEL="mobile client"
''');

    final profile = HostProfile.fromResolved(config.resolve('pi'));

    expect(profile.label, 'pi');
    expect(profile.hostName, '192.0.2.10');
    expect(profile.user, 'codex');
    expect(profile.port, 2222);
    expect(profile.identityFileHint, '~/.ssh/pi');
    expect(profile.appServerMode, AppServerMode.shared);
    expect(profile.customAppServerSocket, isNull);
    expect(profile.environment, {
      'LC_CODEX_BACKEND': 'sub2api',
      'CODEX_LABEL': 'mobile client',
    });
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
    final profile = HostProfile(
      id: 'host-1',
      label: 'Workstation',
      hostName: 'dev.example',
      user: 'coder',
      port: 22,
      authMethod: HostAuthMethod.privateKey,
      identityFileHint: '~/.ssh/id_ed25519',
      appServerMode: AppServerMode.custom,
      customAppServerSocket: '/run/user/1000/codex.sock',
      environment: const {
        'LC_CODEX_BACKEND': 'sub2api',
        'CODEX_LABEL': 'mobile client',
      },
    );

    expect(HostProfile.fromJson(profile.toJson()), profile);
    expect(profile.toJson()['environment'], {
      'LC_CODEX_BACKEND': 'sub2api',
      'CODEX_LABEL': 'mobile client',
    });
    expect(profile.toJson()['appServerMode'], 'custom');
    expect(
      profile.toJson()['customAppServerSocket'],
      '/run/user/1000/codex.sock',
    );
    expect(profile.toJson().keys, isNot(contains('password')));
    expect(profile.toJson().keys, isNot(contains('privateKey')));
  });

  test('loads old profile JSON without an environment', () {
    final profile = HostProfile.fromJson({
      'id': 'legacy',
      'label': 'Legacy host',
      'hostName': 'legacy.example',
      'user': 'coder',
      'port': 22,
      'authMethod': 'password',
    });

    expect(profile.environment, isEmpty);
    expect(profile.appServerMode, AppServerMode.shared);
    expect(profile.customAppServerSocket, isNull);
    expect(profile.windowsAppServerPort, 38765);
    expect(profile.toJson(), isNot(contains('environment')));
  });

  test('round-trips Windows TCP app-server configuration', () {
    final profile = HostProfile(
      id: 'windows',
      label: 'Windows workstation',
      hostName: 'home.example',
      user: 'owner',
      port: 2222,
      appServerMode: AppServerMode.windowsTcp,
      windowsAppServerPort: 40123,
    );

    expect(HostProfile.fromJson(profile.toJson()), profile);
    expect(profile.appServerModeLabel, 'Windows TCP app-server');
    expect(profile.toJson()['windowsAppServerPort'], 40123);
  });

  test('copyWith replaces mode and can clear a custom socket', () {
    final profile = HostProfile(
      id: 'host-1',
      label: 'Workstation',
      hostName: 'dev.example',
      user: 'coder',
      port: 22,
      appServerMode: AppServerMode.custom,
      customAppServerSocket: '/tmp/custom.sock',
    );

    final isolated = profile.copyWith(
      appServerMode: AppServerMode.isolated,
      clearCustomAppServerSocket: true,
    );

    expect(isolated.appServerMode, AppServerMode.isolated);
    expect(isolated.customAppServerSocket, isNull);
    expect(isolated.toJson()['appServerMode'], 'isolated');
    expect(isolated.toJson(), isNot(contains('customAppServerSocket')));
  });

  test('mode and custom socket participate in equality', () {
    HostProfile profile(
      AppServerMode mode, {
      String? socket,
    }) =>
        HostProfile(
          id: 'same-id',
          label: 'Same endpoint',
          hostName: 'host.example',
          user: 'codex',
          port: 22,
          appServerMode: mode,
          customAppServerSocket: socket,
        );

    final shared = profile(AppServerMode.shared);
    final isolated = profile(AppServerMode.isolated);
    final custom = profile(AppServerMode.custom, socket: '/tmp/one.sock');
    final otherCustom = profile(
      AppServerMode.custom,
      socket: '/tmp/two.sock',
    );

    expect(shared, isNot(isolated));
    expect(custom, isNot(otherCustom));
    expect(custom.appServerModeLabel, 'Custom socket');
    expect(isolated.appServerModeLabel, 'Isolated app-server');
  });

  test('copyWith can replace and clear an environment', () {
    final profile = HostProfile(
      id: 'host-1',
      label: 'Workstation',
      hostName: 'dev.example',
      user: 'coder',
      port: 22,
      environment: const {'LC_CODEX_BACKEND': 'sub2api'},
    );

    final replaced = profile.copyWith(environment: const {'MODE': 'review'});
    final cleared = replaced.copyWith(environment: const {});

    expect(replaced.environment, {'MODE': 'review'});
    expect(cleared.environment, isEmpty);
    expect(cleared.toJson(), isNot(contains('environment')));
  });

  test('uses environment map contents for equality and hashCode', () {
    HostProfile profileWith(Map<String, String> environment) => HostProfile(
          id: 'host-1',
          label: 'Workstation',
          hostName: 'dev.example',
          user: 'coder',
          port: 22,
          environment: environment,
        );

    final first = profileWith({
      'LC_CODEX_BACKEND': 'sub2api',
      'CODEX_LABEL': 'mobile client',
    });
    final sameContentsDifferentOrder = profileWith({
      'CODEX_LABEL': 'mobile client',
      'LC_CODEX_BACKEND': 'sub2api',
    });
    final differentValue = profileWith({
      'LC_CODEX_BACKEND': 'official',
      'CODEX_LABEL': 'mobile client',
    });

    expect(first, sameContentsDifferentOrder);
    expect(first.hashCode, sameContentsDifferentOrder.hashCode);
    expect(first, isNot(differentValue));
  });

  test('defensively copies and exposes an immutable environment', () {
    final source = <String, String>{'LC_CODEX_BACKEND': 'sub2api'};
    final profile = HostProfile(
      id: 'host-1',
      label: 'Workstation',
      hostName: 'dev.example',
      user: 'coder',
      port: 22,
      environment: source,
    );

    source['LC_CODEX_BACKEND'] = 'changed';

    expect(profile.environment, {'LC_CODEX_BACKEND': 'sub2api'});
    expect(
      () => profile.environment['ADDED'] = 'value',
      throwsUnsupportedError,
    );
  });
}
