# Stable Android Release Signing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every GitHub Release Android APK/AAB the same retained signing identity so releases after the migration baseline install as upgrades.

**Architecture:** A focused shell helper patches the CI-generated Kotlin Gradle project to load an optional `key.properties`. GitHub Actions restores the retained PKCS#12 keystore from secrets, requires it for tags, and verifies the APK signer fingerprint before publishing.

**Tech Stack:** Bash, Kotlin Gradle DSL, Flutter 3.35.7, Android `apksigner`, GitHub Actions and repository secrets/variables.

---

### Task 1: Specify generated Gradle signing behavior

**Files:**
- Create: `test/tool/configure_android_signing_test.sh`
- Create: `tool/configure_android_signing.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the failing shell regression test**

Create a temporary `build.gradle.kts` containing Flutter's generated
`signingConfig = signingConfigs.getByName("debug")`, invoke the missing helper,
and assert that the output contains `java.util.Properties`, conditional release
configuration, and the debug fallback without containing fixture credentials.

- [ ] **Step 2: Run the test in GitHub CI and verify RED**

Push only the test and CI invocation. Expected: `bash:
tool/configure_android_signing.sh: No such file or directory`.

- [ ] **Step 3: Add the minimal signing configurator**

Implement `tool/configure_android_signing.sh GRADLE_FILE`. It must reject an
unsupported Gradle file, patch exactly one generated debug signing assignment,
and make a second invocation idempotent.

- [ ] **Step 4: Run the shell test in GitHub CI and verify GREEN**

Expected: `configure_android_signing_test: PASS`, followed by the existing
Flutter analyzer and test suite passing.

- [ ] **Step 5: Commit**

```bash
git add tool/configure_android_signing.sh test/tool/configure_android_signing_test.sh .github/workflows/ci.yml
git commit -m "test: specify generated Android signing config"
```

### Task 2: Integrate stable signing into platform generation

**Files:**
- Modify: `tool/prepare_android.sh`
- Modify: `.github/workflows/build.yml`
- Modify: `.gitignore`

- [ ] **Step 1: Invoke the configurator after Flutter generates Android**

Call `tool/configure_android_signing.sh` for the generated Kotlin Gradle file.
Fail clearly if the expected file does not exist.

- [ ] **Step 2: Restore signing inputs without logging them**

Add a workflow step that validates the four secrets as a complete set, decodes
`ANDROID_KEYSTORE_BASE64` into `android/upload-keystore.p12`, and writes
`android/key.properties`. For a tag, missing input must exit nonzero. For other
events, emit only a notice and retain debug fallback.

- [ ] **Step 3: Verify the release signer**

Locate `apksigner` under `$ANDROID_HOME/build-tools`, run `verify --verbose` on
all APKs, extract `Signer #1 certificate SHA-256 digest`, normalize separators
and case, and compare it with `ANDROID_SIGNING_CERT_SHA256` on tag builds.

- [ ] **Step 4: Clean and ignore signing files**

Ignore `android/key.properties` and `android/upload-keystore.p12`. Add an
`if: always()` step that removes both files from the runner.

- [ ] **Step 5: Commit**

```bash
git add tool/prepare_android.sh .github/workflows/build.yml .gitignore
git commit -m "build: use retained Android release signing key"
```

### Task 3: Provision and document the signing identity

**Files:**
- Modify: `docs/BUILDING.md`
- Modify: `README.md`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Generate the retained key outside the repository**

Use OpenSSL to create an RSA-4096 certificate with a long validity period and
export an encrypted PKCS#12 keystore. Store the keystore and mode-`0600`
recovery files under
`~/.config/android-ssh-codex/signing/`.

- [ ] **Step 2: Configure GitHub**

Upload the base64 keystore and three credentials with `gh secret set`. Store the
certificate SHA-256 digest with `gh variable set`. Confirm only names and update
timestamps with `gh secret list` and confirm the public variable value.

- [ ] **Step 3: Document operations and migration**

Document secret names, fingerprint checks, backup/rotation consequences, the
one-time migration reinstall, and the continued unsigned HAP status. Never
include secret values.

- [ ] **Step 4: Bump the version**

Advance the patch version and build number for the first stable-signed release.

- [ ] **Step 5: Commit**

```bash
git add docs/BUILDING.md README.md pubspec.yaml
git commit -m "docs: document stable Android signing migration"
```

### Task 4: Verify and release

**Files:**
- No source files expected.

- [ ] **Step 1: Push the branch and inspect both workflows**

Use GitHub Actions only. Require the shell regression, Flutter analysis/tests,
Android APK/AAB build, OpenHarmony HAP build, and signer verification to pass.

- [ ] **Step 2: Review the diff for secret exposure**

Search tracked files and workflow logs for the generated passwords, base64
keystore, and local recovery path contents. Confirm no sensitive value appears.

- [ ] **Step 3: Merge and tag the baseline release**

Merge the PR, create the next annotated `v*` tag, and wait for the release
workflow to finish.

- [ ] **Step 4: Verify the published APK**

Download the arm64 APK outside the Raspberry Pi workspace and run `apksigner
verify --print-certs`. Its certificate SHA-256 digest must equal the repository
variable. Confirm all expected release assets and checksums exist.

- [ ] **Step 5: Publish migration instructions**

State that this baseline requires the final uninstall for users of old builds,
then provide `adb install -r` as the normal command for every subsequent release.
