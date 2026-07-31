# Android Startup Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Android UI reliably and store credentials with the correct platform plugin.

**Architecture:** `SecureProfileStore` depends on a narrow secure key-value interface. A runtime factory selects the Android or OpenHarmony adapter, while controller initialization converts storage startup failures into visible application state.

**Tech Stack:** Flutter/Dart, `flutter_secure_storage` 9.2.4, `flutter_secure_storage_ohos` 1.0.0, Flutter tests, GitHub Actions.

---

### Task 1: Lock startup failure behavior

**Files:**
- Modify: `test/profiles/host_profile_test.dart`
- Modify: `lib/src/app_controller.dart`

- [ ] Add a `ProfileStore` test double whose `readProfiles` throws and assert that `AppController.initialize` completes with no profiles and a visible storage error.
- [ ] Push the test-only commit and confirm GitHub CI fails because the exception currently escapes.
- [ ] Catch the initialization error in `AppController.initialize`, retain an empty profile list, set the error message, and notify listeners.

### Task 2: Add platform-correct secure storage

**Files:**
- Create: `lib/src/profiles/secure_key_value_store.dart`
- Modify: `lib/src/profiles/profile_store.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `tool/prepare_android.sh`

- [ ] Define `SecureKeyValueStore` with `read`, `write`, and `delete` operations.
- [ ] Implement an Android adapter with `flutter_secure_storage` and an OHOS adapter with `flutter_secure_storage_ohos`.
- [ ] Select the adapter from `Platform.operatingSystem`; reject unsupported targets explicitly.
- [ ] Change `SecureProfileStore` to depend on the interface.
- [ ] Pin `flutter_secure_storage` to 9.2.4 so its platform-interface dependency remains compatible with the OHOS fork.
- [ ] Disable Android application backup in the generated manifest.

### Task 3: Verify and release

**Files:**
- Modify: `docs/BUILDING.md`
- Modify: `.github/workflows/build.yml` only if verification reveals a workflow defect.

- [ ] Push the implementation and confirm formatting, analysis, tests, Android APK/AAB build, and OpenHarmony HAP build pass in GitHub Actions.
- [ ] Merge the fix, tag the next patch release, and confirm the release contains fresh Android APKs and checksums.
