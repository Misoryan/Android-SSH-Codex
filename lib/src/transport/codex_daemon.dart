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

is_our_server_running() {
  [ -r "$pidfile" ] || return 1
  pid=$(cat "$pidfile" 2>/dev/null || true)
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  command=$(tr '\000' ' ' < "/proc/$pid/cmdline")
  case "$command" in
    *"codex app-server"*"unix://$socket"*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -S "$socket" ] && is_our_server_running; then
  printf '%s\n' "$socket"
  exit 0
fi
rm -f "$socket" "$pidfile"

count=0
while ! mkdir "$lock" 2>/dev/null; do
  if [ -S "$socket" ] && is_our_server_running; then
    printf '%s\n' "$socket"
    exit 0
  fi
  count=$((count + 1))
  if [ "$count" -ge 100 ]; then
    if find "$lock" -type d -mmin +1 -print -quit | grep -q . &&
       rmdir "$lock" 2>/dev/null; then
      count=0
      continue
    fi
    printf '%s\n' 'Timed out waiting for Android SSH Codex app-server lock' >&2
    exit 1
  fi
  sleep 0.1
done
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
