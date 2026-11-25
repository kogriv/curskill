#!/bin/sh
# Обёртка бинаря agent. Прокси только если задан CURSOR_STAND_PROXY.
set -eu

if [ -n "${CURSOR_STAND_PROXY:-}" ]; then
  export http_proxy="${http_proxy:-$CURSOR_STAND_PROXY}"
  export https_proxy="${https_proxy:-$CURSOR_STAND_PROXY}"
  export HTTP_PROXY="$http_proxy"
  export HTTPS_PROXY="$https_proxy"
fi
if [ -n "${CURSOR_STAND_SOCKS:-}" ]; then
  export all_proxy="${all_proxy:-$CURSOR_STAND_SOCKS}"
  export ALL_PROXY="$all_proxy"
fi
if [ -n "${CURSOR_STAND_NO_PROXY:-}" ]; then
  export no_proxy="${no_proxy:-$CURSOR_STAND_NO_PROXY}"
  export NO_PROXY="$no_proxy"
fi

REAL="${CURSOR_AGENT_REAL:-}"
if [ -z "$REAL" ] && [ -e "$HOME/.local/bin/cursor-agent" ]; then
  REAL=$(readlink -f "$HOME/.local/bin/cursor-agent")
fi
if [ -z "$REAL" ] || [ ! -x "$REAL" ]; then
  echo "cursor-agent wrapper: нет реального бинаря (CURSOR_AGENT_REAL / ~/.local/bin/cursor-agent)" >&2
  exit 1
fi
exec "$REAL" "$@"
