#!/usr/bin/env bash
set -euo pipefail

digest=$(sed -n -E \
    's/^.*Signer( #[0-9]+)?:?[[:space:]]+certificate SHA-256 digest:[[:space:]]*//p' \
    | sed -n '1p' \
    | tr -d ':[:space:]' \
    | tr '[:upper:]' '[:lower:]')

if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Could not extract an Android signer SHA-256 certificate digest" >&2
    exit 65
fi

printf '%s\n' "$digest"
