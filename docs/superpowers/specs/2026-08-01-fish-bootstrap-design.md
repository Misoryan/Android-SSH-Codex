# Fish-Compatible Bootstrap Design

## Problem

Android SSH Codex v0.1.3 can authenticate to an SSH server but fail before
starting Codex when the remote account uses fish as its login shell. OpenSSH
passes an exec request through that login shell, while the application sends a
POSIX shell script directly. Fish rejects the script before it creates the
application cache directory.

The application then replaces the useful remote failure with `Remote Codex
app-server did not report its socket`. The locked dartssh2 `run()` API combines
stdout and stderr and does not treat a nonzero remote exit as an exception, so
the current byte-returning runner cannot distinguish success from failure.

The reported host-card layout issue was an old APK installed by mistake. The
single-line, stacked mobile host card is already present in v0.1.3 and requires
no further code change.

## Scope

This change will:

- execute the existing bootstrap script through `/bin/sh` independently of the
  account login shell;
- preserve the remote command exit code, exit signal, stdout, and stderr;
- report a bounded, actionable bootstrap failure instead of a generic missing
  socket error;
- cover fish-compatible invocation and structured command failures in tests;
- update the documented remote shell requirement.

It will not change the host-card UI, add arbitrary remote commands, change SSH
authentication, or add new SSH config directives.

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
result type will carry stdout, stderr, exit code, and exit signal into
`CodexDaemon`, keeping dartssh2-specific process handling out of bootstrap
parsing tests.

`CodexDaemon.bootstrap` will return the validated socket path rather than raw
bytes. It will accept only a stdout line ending in `app-server.sock`. A nonzero
exit, an exit signal, or successful completion without a socket path will throw
an error containing a bounded diagnostic derived from stderr, falling back to
stdout only when stderr is empty. Control characters will be normalized and
remote output will be capped so a server cannot flood the UI or logcat.

SSH `SetEnv` rejection handling remains unchanged and continues to avoid
including environment values in errors.

## Testing

Tests will verify that:

- the generated remote command is fixed-shape, decodes to the POSIX bootstrap,
  and does not expose environment values;
- a successful structured SSH result returns the socket path;
- nonzero remote exits and exit signals expose bounded stderr;
- successful completion without a socket reports bounded diagnostic output;
- SSH environment request rejection still produces the existing `AcceptEnv`
  guidance;
- existing tunnel and host-card regression tests continue to pass unchanged.

All formatting, analysis, tests, Android builds, and OpenHarmony builds will run
only in GitHub Actions. No Flutter, Dart, Gradle, Android, or OpenHarmony build
or test command will run on the Raspberry Pi.

## Release

The change will be delivered through a pull request. After CI passes and the PR
is merged, a patch release will be tagged and built by the existing platform
workflow. The release must include split Android APKs, the Android app bundle,
the unsigned OpenHarmony HAP, and checksum files.
