#!/usr/bin/env bash
set -euo pipefail

flutter config --enable-ohos
flutter create \
  --platforms=ohos \
  --org io.github.wkj2333666 \
  --project-name android_ssh_codex \
  .

module="ohos/entry/src/main/module.json5"
if ! grep -q 'ohos.permission.INTERNET' "$module"; then
  sed -i '/"module"[[:space:]]*:[[:space:]]*{/a\    "requestPermissions": [{ "name": "ohos.permission.INTERNET" }],' "$module"
fi

for strings in \
  ohos/AppScope/resources/base/element/string.json \
  ohos/entry/src/main/resources/base/element/string.json; do
  if [[ -f "$strings" ]]; then
    tmp="${strings}.tmp"
    jq '(.string[] | select(.name == "app_name" or .name == "EntryAbility_label" or .name == "entry_MainAbility").value) = "Android SSH Codex"' \
      "$strings" > "$tmp"
    mv "$tmp" "$strings"
  fi
done

