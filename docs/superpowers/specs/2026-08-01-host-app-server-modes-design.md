# Host App-Server Modes Design

## Problem

Android SSH Codex currently starts and owns a private app-server for every host
profile. The private daemon uses
`~/.cache/android-ssh-codex/app-server.sock`, even when Codex Desktop or a local
tool already exposes a compatible app-server under the same remote account.
This splits loaded thread state, subscriptions, active-turn coordination, and
provider-switcher handoff groups by socket.

The app must let each host profile state which app-server it intends to use.
Two profiles may have identical SSH connection settings but select different
app-server modes, so a user can attach to a shared Desktop daemon and retain an
isolated Android daemon on the same machine.

## Decision

Add a required `AppServerMode` to `HostProfile` with exactly three values:

- `shared`: start or reuse the Codex-managed app-server for the effective
  `CODEX_HOME`, then attach to the socket reported by Codex.
- `custom`: attach to an explicitly configured absolute Unix socket path and
  never manage the process behind it.
- `isolated`: use the existing Android-owned daemon, cache directory, socket,
  environment fingerprint, lock, PID, and log lifecycle.

The profile editor always exposes the mode as a single-choice control. Custom
mode also requires an absolute socket path. Mode and custom path belong to the
host profile, not global settings or SSH credentials. Profile IDs remain unique,
so duplicate network endpoints with different labels and modes are valid.

Existing serialized profiles and imported OpenSSH hosts default to `shared`.
Saving an existing profile persists the selected mode explicitly. SSH config
import fills only fields represented by OpenSSH directives and does not change
the mode currently selected in the editor.

## Shared Mode

Shared mode runs this command through the existing SSH command runner and sends
the profile's `SetEnv` values:

```text
codex app-server daemon start
```

Codex 0.146.0 and newer define this as an idempotent lifecycle operation for
Desktop and mobile SSH clients. A successful command writes one JSON object to
stdout. Android parses the object with `jsonDecode`, requires a non-empty
absolute `socketPath`, and uses that exact path for
`codex app-server proxy --sock <path>`.

Android never invokes `restart`, `stop`, `enable-remote-control`, or
`disable-remote-control` in shared mode. An already-running daemon keeps the
environment with which its owner started it. `SetEnv` still reaches both the
idempotent `start` request and every proxy process, allowing users to make the
host profile compatible with wrapper and provider requirements without giving
Android ownership of the shared daemon.

If the installed Codex does not support `app-server daemon start`, shared mode
may attach to the standard existing control socket at
`${CODEX_HOME:-$HOME/.codex}/app-server-control/app-server-control.sock` when a
remote socket probe confirms it exists. It must not start the legacy private
daemon. If neither the lifecycle command nor an existing standard socket is
available, the connection fails with guidance to update Codex, choose Custom,
or choose Isolated.

A successful daemon command followed by a proxy or WebSocket failure is a
shared-daemon failure. Android reports the original bounded stderr, exit status,
or RPC diagnostic and does not hide the problem by creating an isolated daemon.

## Custom Mode

Custom mode requires an absolute Unix socket path in the host profile. Android
does not run a bootstrap or lifecycle command. It opens the existing SSH exec
proxy directly:

```text
codex app-server proxy --sock <custom-path>
```

The path is shell-quoted by the existing command builder. Relative paths, blank
paths, line breaks, NULs, and other control characters are rejected before the
profile is saved. A missing, stale, inaccessible, or incompatible socket is
reported as a custom-socket connection failure; there is no fallback.

This mode supports app-servers launched locally with an explicit
`--listen unix:///absolute/path`, alternative `CODEX_HOME` layouts, and
operator-managed lifecycle systems.

## Isolated Mode

Isolated mode preserves the existing `CodexDaemon.bootstrap` behavior and its
private path:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/android-ssh-codex/app-server.sock
```

Only this mode compares environment fingerprints and restarts an Android-owned
daemon after its effective environment changes. Existing PID validation, stale
lock recovery, permissions, log path, and bounded startup diagnostics remain
unchanged.

Disconnecting the Android client does not stop the isolated daemon, matching the
current reconnect behavior. Shared and custom processes are never treated as
Android-owned, even if Android was the first client to invoke the idempotent
shared start command.

## Components And Data Flow

`HostProfile` owns `appServerMode` and nullable `customAppServerSocket`. JSON
deserialization supplies `shared` when the mode is absent or unknown, while
serialization always writes the selected mode and writes a custom path only in
custom mode. Equality, hashing, copying, SSH import, and profile-store tests
include the new fields.

`ProfileEditor` displays Shared, Custom, and Isolated as a stable single-choice
mode control. It conditionally displays and validates the custom socket input.
The Hosts tab includes a compact mode subtitle so otherwise similar profiles
remain distinguishable without forcing mode text into the user-provided name.

`CodexDaemon` exposes separate operations for shared lifecycle resolution and
the existing isolated bootstrap. Shared lifecycle output is decoded as JSON and
validated without shell text extraction. A narrowly matched unsupported-command
result enables the existing-standard-socket compatibility path; all other
non-zero results remain failures.

`AppController` selects exactly one resolver from the profile mode, obtains a
socket path, starts the existing SSH proxy tunnel, and performs the normal
WebSocket initialize handshake. It does not retry another mode after the
selected mode has resolved or failed.

```text
Host profile
    |
    +-- Shared   -> daemon start JSON -> reported/default control socket
    +-- Custom   -> validated configured socket
    +-- Isolated -> Android bootstrap -> Android cache socket
                                      |
                                      v
                         SSH exec app-server proxy
                                      |
                                      v
                         WebSocket RPC initialization
```

## Failure Handling

Diagnostics identify both the selected mode and the failing stage. Shared JSON
errors distinguish command failure, malformed JSON, missing `socketPath`, and
invalid path. Custom errors name the profile setting without echoing unrelated
environment values. Isolated errors retain the current PID/log diagnostics.

The existing 1,200-character diagnostic bound and control-character
sanitization apply to all remote command failures. No environment values,
passwords, private keys, passphrases, or full SSH commands are logged.

Mode selection is authoritative:

- Shared never silently becomes Isolated.
- Custom never silently becomes Shared or Isolated.
- Isolated never attaches to a shared or custom socket.

## Verification And Release

All Flutter, Dart, Android, and OpenHarmony tests and builds run only in GitHub
Actions. No local Raspberry Pi build or test is permitted.

Focused tests cover:

- profile JSON migration, serialization, copying, equality, and duplicate SSH
  endpoints with independent modes;
- profile editor mode selection, conditional custom-path input, validation, and
  SSH import preserving the selected mode;
- shared command environment propagation and JSON parsing for valid, malformed,
  missing, relative, and control-character socket paths;
- narrowly classified legacy CLI behavior and attachment to an existing standard
  control socket without starting an isolated daemon;
- shared command, proxy, and WebSocket failures never invoking isolated
  bootstrap;
- custom mode bypassing all lifecycle commands and shell-quoting the path;
- isolated mode retaining environment fingerprint restart behavior; and
- Hosts tab mode subtitles remaining horizontal at narrow phone widths.

The full existing CI matrix, analyzer, release signing checks, and Android ABI
builds must pass before publishing the next stable-signed release.

## Compatibility Boundary

Sharing one app-server socket lets Desktop, Android, and local clients observe
the same loaded threads, active turns, subscriptions, and provider-switcher
handoff group. It does not merge different `CODEX_HOME` values or custom sockets.
Users who intentionally configure multiple modes for the same SSH machine are
choosing separate runtime boundaries and must not assume activity coordination
across those sockets.

The Codex daemon lifecycle interface is experimental. JSON parsing therefore
accepts additional unknown fields but requires the documented `socketPath`.
Changes to the required field or command availability fail closed with a clear
upgrade/compatibility diagnostic instead of falling back to another mode.
