# Android SSH Codex Design

## Product boundary

Android SSH Codex is a mobile client for Codex processes that run on a user's
existing SSH host. The application renders a Codex Desktop-inspired task UI,
but never installs, authenticates, or runs Codex on the phone. The first release
targets Android 8+ and OpenHarmony/HarmonyOS NEXT devices supported by
Flutter-OH 3.35.8 from OpenHarmony-TPC. Remote hosts are POSIX systems with OpenSSH,
a current Codex CLI, and a writable home directory.

The first release includes:

- SSH profiles using password or pasted OpenSSH private keys.
- OpenSSH config import for `Host`, `HostName`, `User`, `Port`, `IdentityFile`,
  and one-hop `ProxyJump`, including wildcard resolution and app overrides.
- Trust-on-first-use host-key pinning with an explicit fingerprint prompt.
- A host-scoped task list containing persisted and currently running Codex
  threads, search, status, working directory, and update time.
- New tasks, task history, streamed agent messages, command/file/tool events,
  interrupt, and command/file approval decisions.
- A persistent, app-owned Codex app-server reached only through SSH.
- Android APK/AAB and OpenHarmony HAP artifacts built by GitHub Actions.

The first release excludes a source editor, SFTP browser, Git hosting actions,
cloud relay, account or API-key custody, voice, plugins marketplace UI,
Windows SSH hosts, multi-hop jump chains, and AppGallery/Play Store submission.

## Considered approaches

1. **Flutter UI with direct SSH and Codex app-server (selected).** A pure Dart
   SSH implementation and a shared Flutter UI minimize platform-specific code.
   It supports Android and the OpenHarmony Flutter port while keeping all
   transport traffic inside SSH.
2. **Separate Kotlin and ArkTS applications.** This gives the strongest native
   integration but duplicates the protocol, state machine, UI, and tests. It is
   too expensive for the first release and increases race-fix divergence.
3. **A mobile WebView backed by a remote web bridge.** This resembles
   `friuns2/codex-mobile`, but adds a remotely installed service and another
   authentication surface. It conflicts with the requirement that the mobile
   app only needs SSH and an existing Codex installation.

## Architecture

The code is split into four independently testable boundaries:

- `ssh_config`: parses OpenSSH config text and resolves aliases without I/O.
- `transport`: opens verified SSH connections, optional one-hop jump channels,
  bootstraps the app-owned daemon, and exposes a local TCP-to-remote-Unix tunnel.
- `protocol`: implements Codex's headerless JSON-RPC 2.0 messages, initialization,
  thread APIs, notifications, and server-initiated approval requests.
- `tasks`: reduces snapshots and notifications into immutable UI state.

The UI depends on controller interfaces rather than SSH or WebSocket classes.
Phone layouts use Hosts, Tasks, and Task routes; wide layouts keep the task list
and conversation visible together.

## Coexistence and task ownership

The client must never reuse, replace, signal, or delete another Codex client's
app-server. It creates only this namespaced endpoint:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/android-ssh-codex/app-server.sock
```

Startup uses an atomic `mkdir` lock plus a PID file owned by this application.
Only a PID recorded beside that socket may be checked, and the app never sends
signals to it. If the recorded process is absent, only the namespaced stale
socket and PID are removed. Codex Desktop's default control socket and every
other socket are outside this directory and remain untouched.

Codex persists threads in shared state. The client polls `thread/list` to see
threads created by the CLI, IDE, Desktop, or this app-server. It also calls
`thread/loaded/list` on its own connection:

- A running thread loaded by this app-server is interactive.
- A running thread not loaded by this app-server is externally owned and shown
  read-only. The app never calls `thread/resume`, `turn/start`, `turn/steer`, or
  `turn/interrupt` for it.
- A completed thread can be resumed by this app-server.

This rule prevents simultaneous writers while still showing work owned by
Codex Desktop or another client. External running threads are refreshed by
polling `thread/read`; they become resumable only after their persisted status
is no longer active.

## Race-free state flow

Each host has exactly one `TaskStore`. All WebSocket notifications and refresh
results enter its synchronous reducer. The store maintains a connection epoch,
a refresh generation, and a monotonically increasing event revision.

1. Reconnecting increments the epoch; events from older connections are ignored.
2. Starting a refresh increments the generation and records the event revision.
3. A late refresh is discarded unless its epoch and generation are current.
4. For each thread, snapshot fields are merged only when that thread has not
   received a newer notification since refresh began.
5. Notification deltas are deduplicated by item id and appended exactly once.
6. Only one periodic refresh is in flight; another tick coalesces into one
   follow-up refresh.

Tests cover stale refreshes, reconnect events, snapshot/event interleaving,
duplicate deltas, and externally owned active threads.

## SSH config and security

Users may paste or import OpenSSH config text. Matching applies OpenSSH's
first-value-wins rule across matching `Host` sections. `HostName`, `User`, and
`Port` become connection defaults. `IdentityFile` is shown as metadata because
the path belongs to the source machine; users attach the corresponding key text
to the mobile profile. A single `ProxyJump` alias is resolved through the same
config. Unsupported directives are retained nowhere and surfaced as warnings.

Host keys use trust on first use. The first fingerprint is presented before
acceptance; subsequent mismatches are hard failures. Passwords, private keys,
key passphrases, config text, and known-host fingerprints are stored through the
platform secure-storage plugin. Logs redact credentials and never include RPC
input text by default.

## Daemon and protocol flow

After SSH authentication the bootstrap command creates the namespaced cache
directory with mode `0700`, acquires its atomic lock, and starts:

```sh
codex app-server --listen unix://$SOCKET
```

The process is detached with stdin closed and output redirected to the
namespaced log. The mobile client binds an ephemeral loopback TCP port; every
accepted socket is bridged through `direct-streamlocal@openssh.com` to the
remote Unix socket. A WebSocket connection over that tunnel performs
`initialize` and `initialized`, then reads threads and model metadata.

The stable API surface is used. Unknown item types are rendered as generic
activity rows so newer Codex versions degrade safely. Server-initiated approval
requests remain pending until the user explicitly allows or denies them.

## Error handling

Errors are classified as SSH configuration, host-key, authentication, daemon,
protocol, disconnected, or remote Codex errors. Connection failures keep the
last task snapshot visible with a stale marker. Reconnect uses capped exponential
backoff and never launches a second refresh. An unsupported remote Codex version
shows the exact command and version output needed for diagnosis.

## Verification and releases

No Flutter build or test runs on the Raspberry Pi workspace. GitHub Actions is
the only execution environment for dependency resolution, formatting checks,
analysis, tests, Android build, and OpenHarmony build. Pull requests run static
checks and tests. Tags matching `v*` build signed-or-debug-installable APK/AAB
and HAP assets, generate checksums, and publish a GitHub release. Dependency and
toolchain caches key on lockfiles and pinned SDK revisions.
