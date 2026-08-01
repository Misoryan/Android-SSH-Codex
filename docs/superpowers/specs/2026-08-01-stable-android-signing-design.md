# Stable Android Release Signing Design

## Problem

Android APKs are currently signed by the generated Flutter Android project's
debug signing configuration. GitHub-hosted runners generate a new debug
keystore, so APKs from different workflow runs cannot update one another. A
device reports a signature mismatch and requires uninstalling the existing app,
which also removes app data.

The private key used for the existing `v0.1.4` APK was ephemeral and cannot be
recovered. The first APK using the new signing identity therefore requires one
final uninstall. Every later APK signed by the retained identity can be
installed with `adb install -r`.

## Scope

This change covers Android APKs and AABs distributed through GitHub Releases.
HarmonyOS 4.2 installs these APKs through its Android compatibility layer, so it
benefits from the same stable Android signature.

Native OpenHarmony HAP signing is out of scope. It requires an OpenHarmony or
Huawei signing certificate and provision profile associated with the target
application and devices. The Android PKCS#12 keystore cannot sign a HAP. The workflow keeps
publishing the clearly named unsigned HAP until those distributor-issued
materials are available.

## Signing Identity

Create one RSA-4096 Android release key with a long validity period and export
it as an encrypted PKCS#12 keystore. Keep the keystore and its credentials in
two places only:

1. GitHub Actions repository secrets for automated builds.
2. A local recovery directory outside the repository with mode `0700`; files
   inside use mode `0600`.

The public SHA-256 certificate fingerprint is stored as a GitHub Actions
repository variable. It is not secret and serves as the expected identity for
every release build. Losing the keystore or its credentials permanently breaks
the update chain, so the local recovery directory must be backed up separately.

Required secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Required variable:

- `ANDROID_SIGNING_CERT_SHA256`

## CI Behavior

The Android platform preparation script configures Gradle to use a release
keystore only when `android/key.properties` exists. Pull requests without
secrets continue to compile with Flutter's generated debug signing config, which
keeps public fork CI usable.

The build workflow restores `android/upload-keystore.p12` and writes
`android/key.properties` without logging secret values. Tag builds treat all
four signing secrets and the expected fingerprint as mandatory. Non-tag builds
may fall back to debug signing.

After building, CI uses Android SDK `apksigner` to verify each APK and extract
its signer certificate SHA-256 digest. For tag builds the normalized digest must
equal `ANDROID_SIGNING_CERT_SHA256`; otherwise the job fails before artifacts
reach the release job. AAB signing is performed by the same Gradle release
configuration.

Gradle explicitly loads the keystore as `PKCS12`. Temporary keystore and
property files remain ignored by Git and are deleted in an `always()` cleanup
step.

## Testing

A shell regression test runs against a temporary generated-style Kotlin Gradle
file. It first demonstrates that the current preparation script leaves debug
signing in place, then verifies that the signing configurator:

- loads `key.properties` only when present;
- creates a `release` signing configuration;
- preserves debug fallback for builds without secrets;
- never embeds credentials or absolute secret paths in Gradle source.

GitHub CI runs the shell test. Platform build CI then provides integration
coverage for Gradle configuration, APK/AAB signing, and certificate fingerprint
verification. No Flutter, Android, or OpenHarmony build runs on the Raspberry Pi.

## Release Migration

The next release becomes the signing baseline. Users with `v0.1.4` or older must
uninstall once before installing it because the old key is unavailable. Release
notes must state this explicitly. Starting with that baseline, future releases
can update in place as long as the retained PKCS#12 keystore is used.
