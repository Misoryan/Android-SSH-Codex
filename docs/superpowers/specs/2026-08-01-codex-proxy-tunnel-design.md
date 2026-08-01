# Codex Proxy Tunnel Design

## Problem

The remote SSH login and Codex app-server bootstrap succeed, but the first
WebSocket handshake through `direct-streamlocal@openssh.com` ends with a clean
remote EOF before any HTTP response header arrives. The existing bridge hides
that remote close and the UI can only report the secondary
`Connection closed before full header was received` exception.

The target host permits stream-local forwarding, the Unix socket is created,
and a direct WebSocket handshake against that socket succeeds. Continuing to
retry the same forwarding mechanism would therefore preserve the failing path
without improving diagnostics.

## Decision

Keep the local loopback TCP server and the existing WebSocket/RPC stack. For
each accepted local connection, open an SSH exec session running:

```text
codex app-server proxy --sock <remote-socket-path>
```

Codex 0.146.0 exposes this command specifically to proxy stdio bytes to the
running app-server control socket. The SSH session's stdin and stdout replace
the dartssh2 `forwardLocalUnix` channel while stderr and exit metadata become
structured tunnel failures.

The profile's `SetEnv` values are sent when opening every proxy session, just
as they are during app-server bootstrap. Socket paths are shell-quoted before
being placed in the command.

## Components

- `CodexDaemon.proxyCommand` builds the safely quoted proxy command.
- `SshProxyChannel` defines the byte streams and exit metadata needed by the
  tunnel independently of dartssh2's concrete `SSHSession`.
- `SshUnixTunnel` continues to own the local loopback server, but opens an
  `SSHSession` proxy for each local connection.
- `SshUnixTunnel.firstFailure` reports the first remote proxy failure. The app
  controller races this future against the initial WebSocket handshake so the
  original stderr and exit status reach the UI.

## Failure Handling

An SSH request failure is propagated immediately. If the proxy stdout or SSH
session closes before the local client, the tunnel raises a bounded diagnostic
containing stderr, exit code, and exit signal when available. Normal local
WebSocket closure only tears down that proxy session and is not reported as a
startup failure.

If the installed Codex lacks `app-server proxy`, the UI tells the user that the
remote proxy command failed instead of showing a generic local WebSocket error.

## Testing And Release

All Flutter/Dart tests and Android builds run only in GitHub Actions. A socket
level unit test uses a fake `SshProxyChannel` to reproduce remote EOF with
stderr and verifies that `firstFailure` exposes the original cause. Command
tests cover shell quoting and environment forwarding at the controller call
site. The existing full CI matrix must pass before the stable-signed release is
published.
