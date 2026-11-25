#!/usr/bin/env bash
# poll_stdout_eq: выход сразу при совпадении и отказ только после потолка.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SH="$ROOT/cursor-stand.sh"
fn="$(sed -n '/^poll_stdout_eq()/,/^}/p' "$SH")"
[ -n "$fn" ]
eval "$fn"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CURSOR_STAND_POLL_INTERVAL=0.01

cat >"$tmp/late" <<'EOF'
#!/bin/sh
n=$(cat "$1")
n=$((n + 1))
echo "$n" >"$1"
if [ "$n" -ge 3 ]; then
  echo wanted
else
  echo old
fi
EOF
cat >"$tmp/never" <<'EOF'
#!/bin/sh
n=$(cat "$1")
n=$((n + 1))
echo "$n" >"$1"
echo old
EOF
chmod +x "$tmp/late" "$tmp/never"

echo 0 >"$tmp/c1"
out="$(poll_stdout_eq 1 wanted "$tmp/late" "$tmp/c1")"
[ "$out" = wanted ]
[ "$(cat "$tmp/c1")" = 3 ]

echo 0 >"$tmp/c2"
set +e
out="$(poll_stdout_eq 0.05 wanted "$tmp/never" "$tmp/c2")"
rc=$?
set -e
[ "$rc" = 1 ]
[ "$out" = old ]
[ "$(cat "$tmp/c2")" = 5 ]

grep -q 'SQLITE_UI_WAIT_SEC="${CURSOR_STAND_SQLITE_UI_WAIT_SEC:-60}"' "$SH"
grep -q 'glass_rename "$name" "$nid"' "$SH"
grep -q 'glass_rename "$new" "$id"' "$SH"
grep -q 'poll_stdout_eq "$SQLITE_UI_WAIT_SEC" true' "$SH"
if grep -n 'for i in 1 2 3 4 5 6 7 8 9 10; do' "$SH"; then
  echo "старый опрос 5 с ещё в скрипте" >&2
  exit 1
fi
echo "ok"
