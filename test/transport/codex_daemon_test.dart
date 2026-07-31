import 'package:android_ssh_codex/src/transport/codex_daemon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap is namespaced, locked, and never signals a process', () {
    const script = CodexDaemon.bootstrapScript;

    expect(script, contains('android-ssh-codex'));
    expect(script, contains(r'mkdir "$lock"'));
    expect(script, contains('app-server --listen unix://'));
    expect(script, isNot(contains('kill ')));
    expect(script, isNot(contains('pkill')));
    expect(script, isNot(contains('killall')));
    expect(script, isNot(contains('.codex/app-server.sock')));
  });

  test('bootstrap only removes files below its own base directory', () {
    const script = CodexDaemon.bootstrapScript;

    expect(script, contains(r'rm -f "$socket" "$pidfile"'));
    expect(script, isNot(contains('rm -rf')));
  });
}
