# Fish Bootstrap and Responsive Host Card Design

## Problem

Android SSH Codex v0.1.3 can authenticate to an SSH server but fail before
starting Codex when the remote account uses fish as its login shell. OpenSSH
passes an exec request through that login shell, while the application sends a
POSIX shell script directly. Fish rejects the script before it creates the
application cache directory.

The same release can render a host label one character per line on devices
whose logical width exceeds the current 600 dp host-card breakpoint while a
large system text scale is active. The card selects its single-row desktop
layout even though the label and actions do not fit.

## Scope

This change will:

- execute the existing bootstrap script through `/bin/sh` independently of the
  account login shell;
- preserve the remote command exit code, stdout, and stderr;
- report a bounded, actionable bootstrap failure instead of a generic missing
  socket error;
- use the stacked host-card layout until the content area is genuinely wide;
- cover the observed fish and large-text layouts in automated tests.

It will not add arbitrary remote commands, change SSH authentication, add new
SSH config directives, or redesign the rest of the workspace.

## Remote Bootstrap

`CodexDaemon` will continue to own the bootstrap script and environment
fingerprint. The script bytes will be Base64 encoded locally. The SSH exec
request will contain only a fixed-shape command equivalent to:

```sh
printf '%s' '<base64 payload>' | base64 -d | /bin/sh
```

This command uses syntax accepted by fish and POSIX shells. The decoded script
is parsed only by `/bin/sh`. Environment values remain SSH environment request
data and are not embedded in the command; the payload contains only the
non-secret environment fingerprint.

The SSH adapter will use `SSHClient.runWithResult`. A small application-owned
result type will carry stdout, stderr, and the optional exit code into
`CodexDaemon`, keeping dartssh2-specific process handling out of bootstrap
parsing tests.

`CodexDaemon.bootstrap` will return the validated socket path rather than raw
bytes. It will accept only a stdout line ending in `app-server.sock`. A nonzero
exit, an exit signal, or successful completion without a socket path will throw
an error containing a bounded diagnostic derived from stderr, falling back to
stdout only when stderr is empty. Remote output will be trimmed and capped so a
server cannot flood the UI or logcat.

SSH `SetEnv` rejection handling remains unchanged and continues to avoid
including environment values in errors.

## Host Card Layout

The compact host card remains a two-row layout:

- the first row contains the avatar and an expanded identity column;
- the host label is one line with ellipsis, followed by the endpoint;
- the second row contains edit, menu, and Connect actions.

The single-row layout will be reserved for content widths of at least 800 dp.
This aligns it with the application's desktop breakpoint and prevents a phone,
foldable, or tablet with enlarged text from allocating only one-character
width to the label. The existing desktop presentation remains unchanged when
there is enough space.

## Testing

Tests will verify that:

- the generated remote command is fixed-shape, decodes to the POSIX bootstrap,
  and does not expose environment values;
- a successful structured SSH result returns the socket path;
- nonzero remote exits expose bounded stderr and never silently become a
  missing-socket `Bad state`;
- SSH environment request rejection still produces the existing `AcceptEnv`
  guidance;
- a host card at roughly 700 dp with enlarged text uses the stacked layout,
  keeps the label on one line, and has no Flutter layout exception;
- the existing 360 dp and desktop layout tests continue to pass.

All formatting, analysis, tests, Android builds, and OpenHarmony builds will run
only in GitHub Actions. No Flutter, Dart, Gradle, Android, or OpenHarmony build
or test command will run on the Raspberry Pi.

## Release

The change will be delivered through a pull request. After CI passes and the PR
is merged, a patch release will be tagged and built by the existing platform
workflow. The release must include split Android APKs, the Android app bundle,
the unsigned OpenHarmony HAP, and checksum files.
