final class CodexDaemon {
  const CodexDaemon._();

  static const bootstrapScript = r'''
set -eu
umask 077
base="${XDG_CACHE_HOME:-$HOME/.cache}/android-ssh-codex"
socket="$base/app-server.sock"
pidfile="$base/app-server.pid"
lock="$base/start.lock"
log="$base/app-server.log"
mkdir -p "$base"
chmod 700 "$base"
if [ -S "$socket" ]; then
  printf '%s\n' "$socket"
  exit 0
fi
if ! mkdir "$lock" 2>/dev/null; then
  count=0
  while [ "$count" -lt 100 ]; do
    if [ -S "$socket" ]; then
      printf '%s\n' "$socket"
      exit 0
    fi
    count=$((count + 1))
    sleep 0.1
  done
  if find "$lock" -type d -mmin +1 -print -quit | grep -q .; then
    rmdir "$lock" 2>/dev/null || true
  fi
  printf '%s\n' 'Timed out waiting for Android SSH Codex app-server lock' >&2
  exit 1
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
rm -f "$socket" "$pidfile"
nohup codex app-server --listen "unix://$socket" </dev/null >>"$log" 2>&1 &
printf '%s\n' "$!" >"$pidfile"
count=0
while [ "$count" -lt 100 ]; do
  if [ -S "$socket" ]; then
    printf '%s\n' "$socket"
    exit 0
  fi
  count=$((count + 1))
  sleep 0.1
done
printf '%s\n' "Codex app-server did not create $socket; inspect $log" >&2
exit 1
''';
}
