# Codex Proxy Tunnel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the failing SSH stream-local bridge with Codex's native stdio proxy and expose remote proxy failures during WebSocket startup.

**Architecture:** Keep the local loopback WebSocket endpoint, but back every accepted socket with an SSH exec session running `codex app-server proxy --sock`. Race the initial WebSocket handshake with a tunnel failure future so stderr and exit metadata replace the current secondary HTTP-header error.

**Tech Stack:** Flutter/Dart, dartssh2 2.22.2, Codex app-server 0.146.0, GitHub Actions.

## Global Constraints

- Do not run Flutter, Dart, Android, or OpenHarmony builds or tests on the Raspberry Pi.
- Run every RED/GREEN verification in GitHub Actions.
- Preserve profile `SetEnv` values for bootstrap and proxy sessions.
- Keep the existing stable Android signing identity.
- Do not use subagents.

---

### Task 1: Reproduce The Lost Proxy Failure

**Files:**
- Modify: `test/transport/ssh_unix_tunnel_test.dart`

**Interfaces:**
- Consumes: existing local loopback tunnel behavior.
- Produces: required `SshProxyChannel`, `SshProxyOpener`,
  `SshUnixTunnel.startWithOpener`, and `SshUnixTunnel.firstFailure` behavior.

- [ ] **Step 1: Write the failing socket-level test**

Add a fake proxy channel with controllable stdout, stderr, stdin, completion,
and exit metadata. Connect a real local `Socket` to the tunnel, close the fake
remote side with exit code 127 and stderr `proxy unavailable`, then assert that
`firstFailure` throws a `CodexProxyException` containing both values.

- [ ] **Step 2: Push the test-only commit**

```bash
git add test/transport/ssh_unix_tunnel_test.dart
git commit -m "test: reproduce Codex proxy tunnel EOF"
git push -u origin codex/fix-codex-proxy-tunnel
```

- [ ] **Step 3: Verify RED in GitHub Actions**

Run the repository CI workflow and expect analyzer/test failure because the
new proxy tunnel interfaces do not exist yet.

### Task 2: Implement The SSH Exec Proxy

**Files:**
- Modify: `lib/src/transport/codex_daemon.dart`
- Modify: `lib/src/transport/ssh_unix_tunnel.dart`
- Modify: `lib/src/app_controller.dart`
- Modify: `test/transport/codex_daemon_test.dart`
- Modify: `test/transport/ssh_unix_tunnel_test.dart`
- Modify: `test/app_controller_startup_test.dart`

**Interfaces:**
- Consumes: `SSHClient.execute`, `SSHSession.stdin`, `SSHSession.stdout`,
  `SSHSession.stderr`, `SSHSession.done`, and profile environment maps.
- Produces: `CodexDaemon.proxyCommand(String)`, `SshProxyChannel`,
  `SshProxyOpener`, `SshUnixTunnel.firstFailure`, and proxy-backed local ports.

- [ ] **Step 1: Add command construction tests**

Assert that ordinary socket paths produce
`exec codex app-server proxy --sock '<path>'` and that a single quote in a path
is encoded with the POSIX `'<quote>"<quote>"<quote>'` sequence.

- [ ] **Step 2: Add the minimal command builder**

Add `CodexDaemon.proxyCommand` plus a private POSIX single-quote helper.

- [ ] **Step 3: Replace the forwarding channel**

Adapt `SSHSession` to `SshProxyChannel`, pipe local bytes to session stdin and
session stdout to the local socket, collect bounded stderr, and report early
remote closure through `firstFailure` as `CodexProxyException`.

- [ ] **Step 4: Propagate startup failure and environment**

Pass `profile.environment` into `SshUnixTunnel.start` and race
`WebSocketRpcTransport.connect` with `firstFailure.then` in `AppController`.

- [ ] **Step 5: Commit and push GREEN implementation**

```bash
git add lib test docs/superpowers
git commit -m "fix: tunnel Codex through native SSH proxy"
git push
```

- [ ] **Step 6: Verify GREEN in GitHub Actions**

Require formatting, analyzer, unit/widget tests, workflow tests, and Android
build jobs to pass. Do not run any equivalent locally.

### Task 3: Integrate And Release

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`

**Interfaces:**
- Consumes: stable signing secrets and current release workflow.
- Produces: the next patch release with consistently signed Android APKs.

- [ ] **Step 1: Update version and compatibility note**

Increment the patch version and document that remote Codex must provide
`codex app-server proxy --sock` (Codex 0.146.0 or newer).

- [ ] **Step 2: Verify release metadata in CI**

Push the version commit and require all GitHub Actions checks to pass.

- [ ] **Step 3: Merge and tag**

Merge the pull request, create the matching `v<version>` tag, and push it so
the release workflow creates stable-signed APK artifacts.

- [ ] **Step 4: Verify release artifacts**

Confirm the release workflow succeeded, report the arm64 APK URL and SHA-256,
and verify its certificate SHA-256 remains
`1FFDC122F12EF99917F39697091BFE51334FCC985ACCCE3982A530762880EBC8`.
