#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

gradle_file="$tmp_dir/build.gradle.kts"
cat > "$gradle_file" <<'GRADLE'
plugins {
    id("com.android.application")
}

android {
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
GRADLE

cat > "$tmp_dir/key.properties" <<'PROPERTIES'
storePassword=fixture-password
keyPassword=fixture-password
keyAlias=fixture
storeFile=fixture.p12
storeType=PKCS12
PROPERTIES

bash "$repo_root/tool/configure_android_signing.sh" "$gradle_file"

grep -Fq 'import java.util.Properties' "$gradle_file"
grep -Fq 'val keystorePropertiesFile = rootProject.file("key.properties")' "$gradle_file"
grep -Fq 'create("release")' "$gradle_file"
grep -Fq 'storeType = keystoreProperties["storeType"] as String' "$gradle_file"
grep -Fq 'if (keystorePropertiesFile.exists())' "$gradle_file"
grep -Fq 'signingConfigs.getByName("release")' "$gradle_file"
grep -Fq 'signingConfigs.getByName("debug")' "$gradle_file"

if grep -Fq 'fixture-password' "$gradle_file"; then
    echo "Signing credentials were embedded in Gradle source" >&2
    exit 1
fi

cp "$gradle_file" "$tmp_dir/first-pass.gradle.kts"
bash "$repo_root/tool/configure_android_signing.sh" "$gradle_file"
cmp "$tmp_dir/first-pass.gradle.kts" "$gradle_file"

echo "configure_android_signing_test: PASS"
