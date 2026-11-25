#!/usr/bin/env bash
# Подтянуть этот клон и обновить симлинки скилла.
# Файл хоста, таймер systemd и живой экран не трогает.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "update: $ROOT не git-клон" >&2
  exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "update: в клоне есть незакоммиченные правки, pull не делаю" >&2
  git status --short >&2
  exit 1
fi

git pull --ff-only
"$ROOT/install/install.sh"

host="$(hostname)"
if [ ! -f "$ROOT/config/hosts/${host}.env" ]; then
  echo "update: нет config/hosts/${host}.env — порты и прокси этой машины скрипт не увидит" >&2
  echo "update: образец — config/hosts/example.env.example, в git этот файл не класть" >&2
fi
echo "update: скилл указывает на $ROOT. Таймер и экран не переключались."
