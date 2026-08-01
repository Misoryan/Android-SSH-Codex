#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow="$repo_root/.github/workflows/build.yml"
trusted_ref_condition="if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')"

grep -Fq "$trusted_ref_condition" "$workflow"
grep -Fq 'KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}' "$workflow"
grep -Fq 'if [[ "$GITHUB_REF" == refs/tags/v* ]]' "$workflow"

echo "android_signing_workflow_test: PASS"
