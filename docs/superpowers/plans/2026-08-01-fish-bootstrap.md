# Fish-Compatible Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start the remote Codex app-server when the SSH account uses fish and preserve actionable remote command failures.

**Architecture:** Encode the existing POSIX bootstrap locally and pipe it through `/bin/sh` using an outer command fish can parse. Replace the byte-only command runner with an application-owned structured result, adapt dartssh2 `runWithResult` at the controller boundary, and make `CodexDaemon` return a validated socket path or a bounded diagnostic exception.

**Tech Stack:** Flutter 3.35.7, Dart, dartssh2 2.22.2, POSIX sh, GitHub Actions.

---

## File Structure

- `lib/src/transport/codex_daemon.dart`: Own the shell-independent command wrapper, structured command result, socket parsing, and bounded failure diagnostics.
- `lib/src/app_controller.dart`: Adapt `SSHClient.runWithResult` to `SshCommandResult` and consume the validated socket path.
- `test/transport/codex_daemon_test.dart`: Exercise command encoding, structured success/failure, output bounds, and existing SetEnv behavior.
- `test/app_controller_startup_test.dart`: Lock profile environment propagation through the new structured runner contract.
- `docs/BUILDING.md`: Document `/bin/sh` and Base64 requirements while allowing non-POSIX login shells.
- `pubspec.yaml`: Set the patch release version.

### Task 1: Add Failing Structured Bootstrap Tests

**Files:**
- Modify: `test/transport/codex_daemon_test.dart`
- Modify: `test/app_controller_startup_test.dart`

- [ ] **Step 1: Add the command-wrapper and structured-success tests**

Add `dart:convert` to `test/transport/codex_daemon_test.dart`. Replace byte-only
runner results with this helper:

```dart
SshCommandResult result({
  String stdout = '',
  String stderr = '',
  int? exitCode = 0,
  String? exitSignal,
}) =>
    SshCommandResult(
      stdout: utf8.encode(stdout),
      stderr: utf8.encode(stderr),
      exitCode: exitCode,
      exitSignal: exitSignal,
    );
```

Add a test that extracts the Base64 payload from the exact fixed-shape command,
decodes it, and verifies that it contains the fingerprint assignment and
`CodexDaemon.bootstrapScript` but not `sub2api` or another environment value:

```dart
final command = CodexDaemon.bootstrapCommand(environment);
final match = RegExp(
  r"^printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d \| /bin/sh$",
).firstMatch(command);
expect(match, isNotNull);
final script = utf8.decode(base64Decode(match!.group(1)!));
expect(script, contains(CodexDaemon.bootstrapScript));
expect(script, isNot(contains('sub2api')));
expect(script, isNot(contains('mobile client')));
```

Change the successful bootstrap runner to return:

```dart
return result(stdout: '/home/codex/.cache/android-ssh-codex/app-server.sock\n');
```

and expect `CodexDaemon.bootstrap` to return that socket path as a `String`.

- [ ] **Step 2: Add remote failure and diagnostic-bound tests**

Add tests for these contracts:

```dart
await expectLater(
  CodexDaemon.bootstrap(
    (command, {environment}) async => result(
      stderr: '/bin/sh: codex: not found\n',
      exitCode: 127,
    ),
    environment: const {},
  ),
  throwsA(
    isA<CodexBootstrapException>()
        .having((error) => error.message, 'message', contains('exit code 127'))
        .having((error) => error.message, 'message', contains('codex: not found')),
  ),
);
```

```dart
await expectLater(
  CodexDaemon.bootstrap(
    (command, {environment}) async => result(
      stderr: 'terminated remotely',
      exitCode: null,
      exitSignal: 'KILL',
    ),
    environment: const {},
  ),
  throwsA(
    isA<CodexBootstrapException>().having(
      (error) => error.message,
      'message',
      contains('signal KILL'),
    ),
  ),
);
```

Add a missing-socket test with exit code zero and stderr `socket was not
created`; require that exact diagnostic. Add a 5,000-character stderr test and
require the exception message to be shorter than 1,400 characters. Keep the
existing SSHChannelRequestError tests and update their closures to the new
result type only where a value is returned.

- [ ] **Step 3: Update the controller bootstrap contract test**

In `test/app_controller_startup_test.dart`, make its fake runner return:

```dart
return SshCommandResult(
  stdout: utf8.encode(
    '/home/pi/.cache/android-ssh-codex/app-server.sock\n',
  ),
  stderr: const [],
  exitCode: 0,
  exitSignal: null,
);
```

Capture the returned socket path and assert it equals
`/home/pi/.cache/android-ssh-codex/app-server.sock`. Retain the identity check
that the profile environment map is passed unchanged.

- [ ] **Step 4: Commit and verify RED in GitHub Actions**

```bash
git add test/transport/codex_daemon_test.dart test/app_controller_startup_test.dart
git commit -m "test: reproduce fish bootstrap result loss"
git push -u origin codex/fix-fish-bootstrap-layout
gh pr create --draft --base main --head codex/fix-fish-bootstrap-layout \
  --title "Fix Codex bootstrap for fish SSH accounts" \
  --body "Tests first for fish-compatible bootstrap and structured SSH failures."
gh pr checks --watch
```

Expected: CI fails because `SshCommandResult`, `CodexBootstrapException`, and
the structured `CodexDaemon.bootstrap` contract do not exist yet. Do not run
Flutter or Dart locally.

### Task 2: Implement Shell-Independent Bootstrap

**Files:**
- Modify: `lib/src/transport/codex_daemon.dart`
- Modify: `lib/src/app_controller.dart`

- [ ] **Step 1: Add application-owned command result and exception types**

Add to `codex_daemon.dart`:

```dart
final class SshCommandResult {
  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.exitSignal,
  });

  final List<int> stdout;
  final List<int> stderr;
  final int? exitCode;
  final String? exitSignal;
}

final class CodexBootstrapException implements Exception {
  const CodexBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef SshCommandRunner = Future<SshCommandResult> Function(
  String command, {
  Map<String, String>? environment,
});
```

- [ ] **Step 2: Wrap the POSIX script for fish-compatible execution**

Keep a separate private payload method and make the public command fixed-shape:

```dart
static String _bootstrapPayload(Map<String, String> environment) =>
    "environment_fingerprint='${environmentFingerprint(environment)}'\n"
    '$bootstrapScript';

static String bootstrapCommand(Map<String, String> environment) {
  final payload = base64Encode(utf8.encode(_bootstrapPayload(environment)));
  return "printf '%s' '$payload' | base64 -d | /bin/sh";
}
```

Environment values remain only in the SSH environment request.

- [ ] **Step 3: Parse structured results and bound diagnostics**

Change `CodexDaemon.bootstrap` to return `Future<String>`. After the runner
returns, decode stdout and stderr independently. If `exitCode` is nonzero or
`exitSignal` is present, throw `CodexBootstrapException` with status and the
bounded diagnostic. Otherwise, return the last trimmed stdout line ending in
`app-server.sock`. If absent, throw a diagnostic missing-socket exception.

Use these bounds and normalization rules:

```dart
static const _maxDiagnosticCharacters = 1200;

static String _boundedDiagnostic(List<int> bytes) {
  var text = utf8.decode(bytes, allowMalformed: true).trim();
  text = text.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
    '?',
  );
  if (text.isEmpty) return 'No diagnostic output was returned.';
  if (text.length <= _maxDiagnosticCharacters) return text;
  return '${text.substring(0, _maxDiagnosticCharacters - 3)}...';
}
```

Prefer stderr for diagnostics and use stdout only when stderr is empty. Preserve
the existing `SSHChannelRequestError` to `AcceptEnv` conversion around the
runner call.

- [ ] **Step 4: Adapt dartssh2 at the controller boundary**

Keep `bootstrapCodexForProfile(SshCommandRunner, HostProfile)` testable. In
`_openConnection`, call it with a closure that invokes `runWithResult`:

```dart
final socketPath = await bootstrapCodexForProfile(
  (command, {environment}) async {
    final result = await ssh!.client.runWithResult(
      command,
      environment: environment,
    );
    return SshCommandResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      exitSignal: result.exitSignal?.signalName,
    );
  },
  profile,
);
```

Remove the raw UTF-8 decode and duplicate socket-line parser from
`AppController`.

- [ ] **Step 5: Commit and verify GREEN in GitHub Actions**

```bash
git add lib/src/transport/codex_daemon.dart lib/src/app_controller.dart
git commit -m "fix: run remote bootstrap through POSIX shell"
git push
gh pr checks --watch
```

Expected: formatting, analyzer, and all Flutter tests pass. Android and
OpenHarmony PR builds also pass. Fix only failures attributable to this change
and re-run CI after each commit.

### Task 3: Documentation, Release, and Verification

**Files:**
- Modify: `docs/BUILDING.md`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Update remote host requirements**

Replace `POSIX shell` in `docs/BUILDING.md` with:

```markdown
- `/bin/sh` and a `base64` command. The account login shell may be fish,
  Bash, Zsh, or another shell that supports ordinary commands, quoting, and
  pipelines.
```

Keep the remaining OpenSSH, Codex CLI, writable cache, and provider network
requirements unchanged.

- [ ] **Step 2: Set the patch version**

Set `pubspec.yaml` to:

```yaml
version: 0.1.4+6
```

- [ ] **Step 3: Commit and run final PR verification**

```bash
git add docs/BUILDING.md pubspec.yaml
git commit -m "docs: document fish-compatible remote bootstrap"
git push
gh pr ready
gh pr checks --watch
```

Expected: `Analyze and test`, `Android APK and AAB`, and `OpenHarmony HAP` all
complete successfully on the final commit. Confirm the PR head SHA matches the
checked SHA and review `git diff origin/main...HEAD` before merge.

- [ ] **Step 4: Merge and publish v0.1.4**

```bash
gh pr merge --merge --delete-branch
git switch main
git pull --ff-only
git tag -a v0.1.4 -m "Android SSH Codex v0.1.4"
git push origin v0.1.4
gh run list --branch v0.1.4 --limit 5
```

Watch the tag-triggered Platform builds workflow until Android, OpenHarmony,
and Publish GitHub release all pass. Verify `v0.1.4` is the latest non-draft,
non-prerelease release and that it contains three split APKs, one AAB, one
unsigned HAP, and all checksum files.
