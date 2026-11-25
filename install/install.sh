#!/usr/bin/env bash
# Ставит скилл симлинками. Стенд не поднимает и таймер не переключает.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY=1
fi

link() {
  local dest=$1 src=$2
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "install: $dest существует и это не симлинк — не трогаю" >&2
    exit 1
  fi
  if [ "$DRY" = 1 ]; then
    echo "ln -sfn $src $dest"
  else
    ln -sfn "$src" "$dest"
    echo "install: $dest → $src"
  fi
}

link "$HOME/.cursor/skills/curskill" "$ROOT/skill"
link "$HOME/.claude/skills/curskill" "$ROOT/skill"

host="$(hostname)"
example="$ROOT/config/hosts/${host}.env.example"
if [ ! -f "$example" ]; then
  example="$ROOT/config/hosts/example.env.example"
fi
dest="$ROOT/config/hosts/${host}.env"
if [ ! -f "$dest" ] && [ -f "$example" ]; then
  if [ "$DRY" = 1 ]; then
    echo "cp $example $dest"
  else
    cp "$example" "$dest"
    echo "install: $dest (gitignore)"
  fi
elif [ ! -f "$example" ]; then
  echo "install: нет $example — профиль машины не скопирован" >&2
fi

echo "CURSOR_STAND_SH=$ROOT/automation/cursor-stand.sh"
echo "Таймер systemd и прежняя копия скрипта этим не переключаются."
