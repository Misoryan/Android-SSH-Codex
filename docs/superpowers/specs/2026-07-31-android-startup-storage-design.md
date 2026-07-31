# Android Startup Storage Design

## Problem

The application imports `flutter_secure_storage_ohos` as its only secure
storage implementation. That package contains an OpenHarmony plugin but no
Android plugin. Android therefore throws when the application reads profiles,
and because the read happens before `runApp`, the first Flutter frame is never
rendered.

## Design

Introduce a small secure key-value interface used by `SecureProfileStore`.
Select the official `flutter_secure_storage` implementation on Android and the
existing OpenHarmony implementation on OHOS. Keep credentials encrypted on both
platforms and disable Android application backup so encrypted preferences are
not restored without their matching keystore key.

Initialization will catch profile-store failures, expose a user-visible error,
and continue with an empty host list. A storage failure must never prevent the
application from rendering its first workspace.

## Verification

Add a controller regression test with a store that throws during startup. The
test must prove initialization completes with an empty host list and an error.
GitHub Actions remains the only environment that runs Flutter tests and Android
or OpenHarmony builds.
