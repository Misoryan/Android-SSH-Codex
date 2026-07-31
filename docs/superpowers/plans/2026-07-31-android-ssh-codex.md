# Android SSH Codex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a mobile Codex client that safely controls a dedicated remote app-server through SSH while showing all persisted and running server tasks.

**Architecture:** A Flutter application separates OpenSSH config parsing, verified SSH/tunneling, Codex JSON-RPC, race-free task reduction, secure profile persistence, and responsive UI. A namespaced remote Unix socket coexists with every other Codex client; active externally owned threads are visible but read-only.

**Tech Stack:** Flutter/Dart, dartssh2, web_socket_channel, flutter_secure_storage OpenHarmony port, Material 3, flutter_test, GitHub Actions.

---

### Task 1: Repository and executable specification

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `test/ssh_config/ssh_config_parser_test.dart`
- Create: `test/tasks/task_reducer_test.dart`
- Create: `test/protocol/json_rpc_client_test.dart`

- [ ] Write parser tests for aliases, wildcard precedence, quoted values,
  identity files, and one-hop ProxyJump.
- [ ] Write reducer tests that prove stale refreshes, old connection events,
  duplicate deltas, and external ownership cannot overwrite current state.
- [ ] Write JSON-RPC tests for ids, results, errors, notifications, and
  server-initiated approval requests.
- [ ] Push the tests without implementations and confirm the Tests workflow
  fails because the referenced production libraries do not exist.

### Task 2: SSH config and domain model

**Files:**
- Create: `lib/src/ssh_config/ssh_config.dart`
- Create: `lib/src/ssh_config/ssh_config_parser.dart`
- Create: `lib/src/profiles/host_profile.dart`

- [ ] Implement tokenization with quotes, comments, and whitespace.
- [ ] Implement case-insensitive directives and first-value-wins matching.
- [ ] Resolve exact and wildcard aliases plus one ProxyJump alias.
- [ ] Run the remote Tests workflow and confirm parser tests pass.

### Task 3: Race-free task state

**Files:**
- Create: `lib/src/tasks/task_models.dart`
- Create: `lib/src/tasks/task_reducer.dart`
- Create: `lib/src/tasks/task_store.dart`

- [ ] Define immutable thread, turn, item, ownership, and connection models.
- [ ] Implement epoch and refresh-generation guards.
- [ ] Merge snapshots only when a thread revision is not newer than refresh
  start, and deduplicate delta fragments by event sequence.
- [ ] Derive read-only ownership from active status and `thread/loaded/list`.
- [ ] Run the remote Tests workflow and confirm reducer tests pass.

### Task 4: Codex JSON-RPC client

**Files:**
- Create: `lib/src/protocol/rpc_transport.dart`
- Create: `lib/src/protocol/json_rpc_client.dart`
- Create: `lib/src/protocol/codex_remote_api.dart`
- Create: `lib/src/protocol/codex_events.dart`

- [ ] Correlate request ids and fail all pending requests on disconnect.
- [ ] Parse notifications separately from server requests carrying ids.
- [ ] Implement initialize, thread list/read/start/resume, loaded list, turn
  start/interrupt, and approval response methods.
- [ ] Convert the stable notification subset into reducer events and retain an
  unknown-event fallback.
- [ ] Run the remote Tests workflow and confirm protocol tests pass.

### Task 5: Secure profiles and SSH transport

**Files:**
- Create: `lib/src/profiles/profile_store.dart`
- Create: `lib/src/transport/ssh_connector.dart`
- Create: `lib/src/transport/codex_daemon.dart`
- Create: `lib/src/transport/ssh_unix_tunnel.dart`
- Create: `test/transport/codex_daemon_test.dart`

- [ ] Persist profiles, secrets, imported config, and fingerprints only via
  secure storage.
- [ ] Require explicit first-use host-key acceptance and reject mismatches.
- [ ] Connect directly or through one ProxyJump using nested SSH channels.
- [ ] Generate a fixed POSIX bootstrap script that touches only the app's cache
  directory, uses an atomic lock, never signals a PID, and starts the unique
  Unix socket only when absent.
- [ ] Bridge an ephemeral loopback TCP server to remote Unix channels.
- [ ] Run the remote Tests workflow and confirm bootstrap safety tests pass.

### Task 6: Application controller and UI

**Files:**
- Create: `lib/main.dart`
- Create: `lib/src/app.dart`
- Create: `lib/src/app_controller.dart`
- Create: `lib/src/ui/hosts_view.dart`
- Create: `lib/src/ui/tasks_view.dart`
- Create: `lib/src/ui/task_view.dart`
- Create: `lib/src/ui/profile_editor.dart`
- Create: `lib/src/ui/widgets/connection_badge.dart`
- Create: `lib/src/ui/widgets/timeline_item.dart`
- Create: `test/ui/app_smoke_test.dart`

- [ ] Add onboarding and SSH config import/profile editing.
- [ ] Add responsive host/task/task-detail navigation.
- [ ] Add task search, status/ownership labels, new/resume flows, streaming
  timeline, composer, interrupt, reconnect, and approval controls.
- [ ] Ensure external active tasks visibly remain read-only.
- [ ] Run the remote Tests workflow and confirm widget tests pass.

### Task 7: CI, platform generation, and release

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/workflows/ohos.yml`
- Create: `tool/prepare_android.sh`
- Create: `tool/prepare_ohos.sh`
- Create: `docs/BUILDING.md`

- [ ] Pin Flutter and OpenHarmony Flutter revisions.
- [ ] Generate platform shells in CI, then apply deterministic app id,
  permissions, labels, minimum SDK, and signing configuration.
- [ ] Cache Pub, Gradle, OpenHarmony SDK, OHPM, and Flutter engine artifacts with
  lockfile/revision keys.
- [ ] Upload APK, AAB, HAP, test reports, and SHA-256 checksums.
- [ ] Publish tag artifacts through GitHub Releases.

### Task 8: Public repository and remote verification

**Files:**
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`

- [ ] Initialize Git with `main`, commit the MIT-licensed source, and create the
  public `Android-SSH-Codex` repository with GitHub CLI.
- [ ] Push and monitor all workflows; diagnose from logs and patch until tests,
  Android build, and OpenHarmony build are green.
- [ ] Tag `v0.1.0`, verify release checksums and downloadable assets, and record
  the exact CI evidence in the release notes.

