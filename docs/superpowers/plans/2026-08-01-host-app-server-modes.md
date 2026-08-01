# Host App-Server Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let every SSH host explicitly connect through a shared Codex daemon, an operator-managed custom socket, or an Android-owned isolated daemon.

**Architecture:** Persist the selected mode and optional custom socket on `HostProfile`. Resolve exactly one socket according to that mode before opening the existing SSH exec proxy tunnel; shared mode uses Codex's idempotent daemon lifecycle JSON, custom mode only attaches, and isolated mode retains the current bootstrap.

**Tech Stack:** Flutter 3.35.7, Dart, dartssh2, Codex app-server daemon JSON lifecycle, GitHub Actions.

## Global Constraints

- `shared`, `custom`, and `isolated` are the only modes and are explicitly selected per Host.
- Existing profiles and imported SSH aliases default to `shared`.
- No selected mode may silently fall back to another mode.
- Shared and custom modes never restart or stop an app-server.
- All Flutter, Dart, Android, and OpenHarmony tests and builds run only in GitHub Actions, never on the Raspberry Pi.
- Do not use subagents; execute inline in `codex/shared-app-server-modes`.

---

### Task 1: RED Regression Suite

**Files:**
- Modify: `test/profiles/host_profile_test.dart`
- Modify: `test/transport/codex_daemon_test.dart`
- Modify: `test/app_controller_startup_test.dart`
- Modify: `test/ui/profile_editor_test.dart`
- Modify: `test/ui/app_smoke_test.dart`

**Interfaces:**
- Consumes: existing `HostProfile`, `CodexDaemon`, `bootstrapCodexForProfile`, `ProfileEditor`, and Hosts view APIs.
- Produces: failing specifications for `AppServerMode`, `customAppServerSocket`, `CodexDaemon.startShared`, mode dispatch, mode editor controls, and host mode labels.

- [ ] **Step 1: Write profile behavior tests**

Add assertions equivalent to:

```dart
expect(HostProfile.fromJson(legacy).appServerMode, AppServerMode.shared);
expect(HostProfile.fromResolved(host).appServerMode, AppServerMode.shared);

final custom = HostProfile(
  id: 'custom',
  label: 'Custom',
  hostName: 'host',
  user: 'codex',
  port: 22,
  appServerMode: AppServerMode.custom,
  customAppServerSocket: '/run/user/1000/codex.sock',
);
expect(HostProfile.fromJson(custom.toJson()), custom);
expect(custom.copyWith(appServerMode: AppServerMode.isolated),
    isNot(custom));
```

- [ ] **Step 2: Write resolver and dispatch tests**

Cover valid shared JSON, malformed JSON, missing/relative `socketPath`, environment forwarding, custom mode avoiding the runner, isolated mode retaining the bootstrap command, and shared failure never invoking isolated bootstrap. The wished-for dispatcher is:

```dart
final socket = await resolveCodexSocketForProfile(run, profile);
```

The shared success fixture is:

```json
{"backend":"pid","socketPath":"/home/codex/.codex/app-server-control/app-server-control.sock","cliVersion":"0.146.0","started":true}
```

- [ ] **Step 3: Write editor and host-list tests**

Assert the editor exposes `Shared`, `Custom`, and `Isolated`, requires an absolute custom path only in Custom mode, preserves the selected mode during SSH config import, saves the mode on the returned profile, and renders a horizontal `Shared app-server`, `Custom socket`, or `Isolated app-server` subtitle on a 360 px host card.

- [ ] **Step 4: Commit and push RED tests**

```bash
git add test
git commit -m "test: specify host app-server modes"
git push -u origin codex/shared-app-server-modes
```

Open a draft PR and run GitHub Actions. Expected: CI fails because `AppServerMode`, `customAppServerSocket`, shared resolution, and UI controls do not exist. Confirm the failure is caused by missing production behavior, not malformed tests.

### Task 2: Host Profile Model

**Files:**
- Modify: `lib/src/profiles/host_profile.dart`

**Interfaces:**
- Consumes: `ResolvedSshHost` from the existing OpenSSH parser.
- Produces: `enum AppServerMode { shared, custom, isolated }`, `HostProfile.appServerMode`, `HostProfile.customAppServerSocket`, `HostProfile.appServerModeLabel`, and compatible JSON migration.

- [ ] **Step 1: Add the minimal enum and fields**

Use `shared` defaults in the public constructor, `fromResolved`, and `fromJson` fallback. Serialize `appServerMode` on every profile and serialize `customAppServerSocket` only when mode is Custom and the value is non-null.

- [ ] **Step 2: Update copy/equality/hash behavior**

Make `copyWith` able to set a mode, set a socket, and clear a socket. Include both values in equality and `hashCode`. Provide these exact display labels:

```dart
shared   -> 'Shared app-server'
custom   -> 'Custom socket'
isolated -> 'Isolated app-server'
```

- [ ] **Step 3: Commit the model implementation**

```bash
git add lib/src/profiles/host_profile.dart
git commit -m "feat: persist host app-server modes"
```

### Task 3: Socket Resolution

**Files:**
- Modify: `lib/src/transport/codex_daemon.dart`
- Modify: `lib/src/app_controller.dart`

**Interfaces:**
- Consumes: `SshCommandRunner`, `SshCommandResult`, `HostProfile.appServerMode`, and the profile environment.
- Produces: `CodexDaemon.startShared`, `resolveCodexSocketForProfile`, and mode-specific diagnostics.

- [ ] **Step 1: Implement shared lifecycle parsing**

Run the shell-wrapped equivalent of:

```text
exec codex app-server daemon start
```

Pass the profile environment as the SSH environment. On exit zero, decode stdout with `jsonDecode`, require a map with an absolute, control-free `socketPath`, and return it. Ignore unknown JSON fields and successful stderr warnings.

- [ ] **Step 2: Preserve existing SSH environment rejection handling**

Extract the current `SSHChannelRequestError` translation so shared and isolated commands both report rejected `SetEnv NAME` without exposing values.

- [ ] **Step 3: Attach an old CLI only to its existing standard socket**

When the daemon command fails specifically because `app-server daemon` is an
unknown subcommand, run a bounded POSIX probe that resolves
`${CODEX_HOME:-$HOME/.codex}/app-server-control/app-server-control.sock`, requires
`-S`, and prints the path. Return that existing socket without starting any
process. Treat every other daemon error, an absent socket, or malformed probe
output as a Shared failure that recommends updating Codex, Custom, or Isolated.

- [ ] **Step 4: Implement explicit mode dispatch**

```dart
Future<String> resolveCodexSocketForProfile(
  SshCommandRunner run,
  HostProfile profile,
) => switch (profile.appServerMode) {
  AppServerMode.shared => CodexDaemon.startShared(
      run,
      environment: profile.environment,
    ),
  AppServerMode.custom => Future.value(
      validateCustomAppServerSocket(profile.customAppServerSocket),
    ),
  AppServerMode.isolated => CodexDaemon.bootstrap(
      run,
      environment: profile.environment,
    ),
};
```

Custom mode must not call the runner. Shared failures must propagate and must not call `bootstrap`.

- [ ] **Step 5: Route controller startup through the dispatcher**

Replace `bootstrapCodexForProfile` with `resolveCodexSocketForProfile` at the existing `remoteAppServer` stage while preserving environment forwarding into every proxy SSH session.

- [ ] **Step 6: Commit transport implementation**

```bash
git add lib/src/transport/codex_daemon.dart lib/src/app_controller.dart
git commit -m "feat: resolve app-server by host mode"
```

### Task 4: Profile Editor And Hosts View

**Files:**
- Modify: `lib/src/ui/profile_editor.dart`
- Modify: `lib/src/ui/hosts_view.dart`

**Interfaces:**
- Consumes: `AppServerMode`, `HostProfile.appServerModeLabel`, and `customAppServerSocket`.
- Produces: host-level mode controls, custom socket validation, and scannable host mode subtitles.

- [ ] **Step 1: Add the mode control**

Initialize editor state from the profile or Shared. Add a three-way `SegmentedButton<AppServerMode>` with icons and the labels `Shared`, `Custom`, and `Isolated`. Keep stable responsive sizing and show no instructional feature copy.

- [ ] **Step 2: Add conditional custom socket input**

Show `App-server Unix socket` only for Custom. Validate trimmed input as a non-empty absolute Unix path without control characters. When saving non-Custom modes, persist a null custom socket.

- [ ] **Step 3: Preserve mode during SSH import**

Do not overwrite editor mode or custom path in `_import`; the import operation only replaces OpenSSH-derived fields.

- [ ] **Step 4: Add mode subtitle to host rows**

Render `profile.appServerModeLabel` as compact secondary text below the endpoint while preserving the existing responsive horizontal name layout and action row.

- [ ] **Step 5: Commit UI implementation**

```bash
git add lib/src/ui/profile_editor.dart lib/src/ui/hosts_view.dart
git commit -m "feat: configure app-server mode per host"
```

### Task 5: GREEN CI And Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/BUILDING.md`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: the completed mode behavior.
- Produces: public usage guidance and the next patch release metadata.

- [ ] **Step 1: Document the three modes**

Explain Shared as the default for Desktop/local daemon reuse, Custom as attach-only, and Isolated as Android-owned. State that duplicate Hosts may point to the same SSH endpoint with different modes.

- [ ] **Step 2: Bump the patch version**

Advance the app from `0.1.6+8` to `0.1.7+9` without changing signing identity or package ID.

- [ ] **Step 3: Push implementation and inspect GitHub Actions**

```bash
git push
gh pr checks --watch
```

Required GREEN evidence: dependency lock unchanged, signing tool tests pass, Dart formatting passes, analyzer passes, all Flutter tests pass, and Android build matrix passes. Fix failures with test-first regression changes and repeat CI.

- [ ] **Step 4: Review the full diff**

Run read-only checks only on the Raspberry Pi:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline origin/main..HEAD
```

Do not run Flutter, Dart, Android, or OpenHarmony commands locally.

- [ ] **Step 5: Complete the branch**

After fresh GitHub verification, use the finishing-a-development-branch workflow to merge the PR, tag `v0.1.7`, publish the stable-signed release, and report the arm64 APK URL, SHA-256, and unchanged certificate SHA-256.
