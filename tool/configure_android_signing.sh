#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <build.gradle.kts>" >&2
    exit 64
fi

gradle_file=$1
marker='// Android SSH Codex stable release signing'

if [[ ! -f "$gradle_file" ]]; then
    echo "Android Gradle file not found: $gradle_file" >&2
    exit 66
fi

if grep -Fq "$marker" "$gradle_file"; then
    exit 0
fi

debug_signing='signingConfig = signingConfigs.getByName("debug")'
if [[ $(grep -Fc "$debug_signing" "$gradle_file") -ne 1 ]]; then
    echo "Unsupported Android Gradle signing layout: $gradle_file" >&2
    exit 65
fi

header_file=$(mktemp)
signing_file=$(mktemp)
output_file=$(mktemp)
trap 'rm -f "$header_file" "$signing_file" "$output_file"' EXIT

cat > "$header_file" <<'GRADLE'
// Android SSH Codex stable release signing
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

GRADLE

cat > "$signing_file" <<'GRADLE'
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

GRADLE

awk -v header="$header_file" -v signing="$signing_file" '
    !header_inserted && /^plugins[[:space:]]*\{/ {
        while ((getline line < header) > 0) print line
        close(header)
        header_inserted = 1
    }
    {
        print
    }
    !signing_inserted && /^android[[:space:]]*\{/ {
        while ((getline line < signing) > 0) print line
        close(signing)
        signing_inserted = 1
    }
    END {
        if (!header_inserted || !signing_inserted) exit 65
    }
' "$gradle_file" > "$output_file" || {
    echo "Unsupported Android Gradle structure: $gradle_file" >&2
    exit 65
}

sed -i \
    's/signingConfig = signingConfigs.getByName("debug")/signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")/' \
    "$output_file"

mv "$output_file" "$gradle_file"
