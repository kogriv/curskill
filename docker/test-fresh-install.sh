#!/usr/bin/env bash
# Прогон установки с нуля в контейнере. Хостовый стенд и клон не меняет:
# репозиторий уходит внутрь архивом, файл хоста обратно не возвращается.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=curskill-install:bookworm
BARE=debian:bookworm-slim
SNAP=$(mktemp -d)
trap 'rm -rf "$SNAP"' EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "нет docker" >&2
  exit 1
fi

before=$(find "$ROOT/config/hosts" -name '*.env' ! -name '*.env.example' | wc -l)

tar -C "$ROOT" \
  --exclude=.git \
  --exclude=__pycache__ \
  --exclude='*.pyc' \
  --exclude='*.env' \
  -cf - . | tar -C "$SNAP" -xf -

echo "=== образ $IMAGE ==="
docker build -t "$IMAGE" -f "$ROOT/docker/Dockerfile" "$ROOT/docker"

run_copy() {
  local image=$1
  shift
  tar -C "$SNAP" -cf - . | docker run --rm -i --network none \
    --hostname curskill-test \
    "$image" "$@"
}

echo "=== пустой Debian: setup.sh должен отказаться ==="
set +e
bare=$(run_copy "$BARE" bash -c \
  'mkdir -p /tmp/curskill && tar -C /tmp/curskill -xf - && bash /tmp/curskill/skill/scripts/setup.sh' \
  2>&1)
bare_code=$?
set -e
printf '%s\n' "$bare"
test "$bare_code" -ne 0
printf '%s\n' "$bare" | grep -F 'нет xdotool' >/dev/null

echo "=== образ с пакетами ==="
run_copy "$IMAGE" bash -c \
  'mkdir -p /tmp/curskill && tar -C /tmp/curskill -xf - && bash /tmp/curskill/docker/check-ready.sh'

after=$(find "$ROOT/config/hosts" -name '*.env' ! -name '*.env.example' | wc -l)
test "$before" = "$after"

echo "test-fresh-install: ok"
