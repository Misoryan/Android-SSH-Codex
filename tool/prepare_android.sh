#!/usr/bin/env bash
set -euo pipefail

flutter create \
  --platforms=android \
  --org io.github.wkj2333666 \
  --project-name android_ssh_codex \
  .

# flutter create adds a starter test for a MyApp class this project does not use.
rm -f test/widget_test.dart

manifest="android/app/src/main/AndroidManifest.xml"
if ! grep -q 'android.permission.INTERNET' "$manifest"; then
  sed -i '/<manifest/a\    <uses-permission android:name="android.permission.INTERNET" />' "$manifest"
fi
for permission in \
  android.permission.FOREGROUND_SERVICE \
  android.permission.FOREGROUND_SERVICE_SPECIAL_USE \
  android.permission.WAKE_LOCK; do
  if ! grep -q "$permission" "$manifest"; then
    sed -i "/<manifest/a\\    <uses-permission android:name=\"$permission\" />" "$manifest"
  fi
done
if ! grep -q 'ConnectionForegroundService' "$manifest"; then
  sed -i '/<\/application>/i\        <service\n            android:name=".ConnectionForegroundService"\n            android:exported="false"\n            android:foregroundServiceType="specialUse">\n            <property\n                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\n                android:value="Maintains a user-requested remote SSH session" />\n        </service>' "$manifest"
fi
if ! grep -q 'android:allowBackup' "$manifest"; then
  sed -i '/<application/a\        android:allowBackup="false"' "$manifest"
fi
sed -i 's/android:label="android_ssh_codex"/android:label="Android SSH Codex"/' "$manifest"

kotlin_dir="android/app/src/main/kotlin/io/github/wkj2333666/android_ssh_codex"
mkdir -p "$kotlin_dir"
cat > "$kotlin_dir/MainActivity.kt" <<'KOTLIN'
package io.github.wkj2333666.android_ssh_codex

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.github.wkj2333666.android_ssh_codex/connection_service",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, ConnectionForegroundService::class.java).apply {
                        putExtra("hostLabel", call.argument<String>("hostLabel"))
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, ConnectionForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
KOTLIN

cat > "$kotlin_dir/ConnectionForegroundService.kt" <<'KOTLIN'
package io.github.wkj2333666.android_ssh_codex

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class ConnectionForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Remote connection", NotificationManager.IMPORTANCE_LOW),
        )
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ssh-connection")
            .apply { acquire() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val hostLabel = intent?.getStringExtra("hostLabel")?.takeIf { it.isNotBlank() }
        val detail = hostLabel?.let { "Connected to $it" } ?: "Remote SSH connection active"
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle("Android SSH Codex")
            .setContentText(detail)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "remote_connection"
        private const val NOTIFICATION_ID = 1001
    }
}
KOTLIN

for gradle_file in android/app/build.gradle.kts android/app/build.gradle; do
  if [[ -f "$gradle_file" ]]; then
    sed -i \
      -e 's/minSdk = flutter.minSdkVersion/minSdk = 26/' \
      -e 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 26/' \
      "$gradle_file"
  fi
done

gradle_file="android/app/build.gradle.kts"
if [[ ! -f "$gradle_file" ]]; then
  echo "Expected generated Kotlin Android Gradle file: $gradle_file" >&2
  exit 1
fi
bash tool/configure_android_signing.sh "$gradle_file"
