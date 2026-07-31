# Contributing

Open an issue before broad product or protocol changes. Keep the mobile client
inside the documented boundary: direct SSH transport, no hosted relay, and no
mobile Codex runtime.

Every behavior change needs a failing test first. Pull requests must pass both
GitHub Actions workflows. Do not commit generated `android/`, `ohos/`, signing
keys, provisioning profiles, credentials, host fingerprints, or private SSH
configuration.

Protocol changes should remain compatible with the stable Codex app-server API.
Unknown notifications and items must degrade to visible generic activity rather
than crashing or silently disappearing.

