#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
extractor="$repo_root/tool/extract_android_cert_sha256.sh"
expected=1ffdc122f12ef99917f39697091bfe51334fcc985accce3982a530762880ebc8

v2_report='Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
V2 Signer: certificate SHA-256 digest: 1ffdc122f12ef99917f39697091bfe51334fcc985accce3982a530762880ebc8'

numbered_report='Signer #1 certificate SHA-256 digest: 1F:FD:C1:22:F1:2E:F9:99:17:F3:96:97:09:1B:FE:51:33:4F:CC:98:5A:CC:CE:39:82:A5:30:76:28:80:EB:C8'

[[ $(printf '%s\n' "$v2_report" | bash "$extractor") == "$expected" ]]
[[ $(printf '%s\n' "$numbered_report" | bash "$extractor") == "$expected" ]]

if printf '%s\n' 'Verifies' | bash "$extractor"; then
    echo "Missing certificate digest was accepted" >&2
    exit 1
fi

echo "extract_android_cert_sha256_test: PASS"
