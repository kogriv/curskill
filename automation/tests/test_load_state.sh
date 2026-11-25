#!/usr/bin/env bash
# load_state не исполняет state.env и не подменяет дисплей.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fn=$(awk '
  /^load_state\(\)/ {p=1}
  p {print}
  p && /^}/ {exit}
' "$root/automation/cursor-stand.sh")
# shellcheck disable=SC1090
eval "$fn"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
STATE="$tmp/state.env"
DISP=:105
cat >"$STATE" <<'EOF'
DISPLAY=:1
XSERVER=xorg-nvidia
XSERVER_PID=99
DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/bus
EOF
load_state
test "$DISP" = ":105"
test "$XSERVER" = "xorg-nvidia"
test "$XSERVER_PID" = "99"
test "$DBUS_SESSION_BUS_ADDRESS" = "unix:path=/tmp/bus"

printf 'DBUS_SESSION_BUS_ADDRESS=$(id)\n' >"$STATE"
if load_state; then
  echo "подстановка должна была отказать" >&2
  exit 1
fi
echo "load_state ok"
