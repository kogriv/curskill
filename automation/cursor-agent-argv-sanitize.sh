# cursor-stand argv-sanitize: --api-key -> CURSOR_API_KEY
# Вставляется в лаунчер cursor-agent. Ключ уходит из argv в окружение.
# Уже запущенный процесс этот блок не получает.
SANITIZED_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --api-key)
      if [ "$#" -ge 2 ]; then
        if [ -z "${CURSOR_API_KEY:-}" ]; then
          export CURSOR_API_KEY="$2"
        elif [ "$CURSOR_API_KEY" != "$2" ]; then
          echo "cursor-agent: CURSOR_API_KEY уже задан и не совпадает с --api-key" >&2
          exit 1
        fi
        shift 2
      else
        SANITIZED_ARGS+=("$1")
        shift
      fi
      ;;
    --api-key=*)
      _argv_key="${1#--api-key=}"
      if [ -z "${CURSOR_API_KEY:-}" ]; then
        export CURSOR_API_KEY="$_argv_key"
      elif [ "$CURSOR_API_KEY" != "$_argv_key" ]; then
        echo "cursor-agent: CURSOR_API_KEY уже задан и не совпадает с --api-key" >&2
        exit 1
      fi
      unset _argv_key
      shift
      ;;
    *)
      SANITIZED_ARGS+=("$1")
      shift
      ;;
  esac
done
set -- "${SANITIZED_ARGS[@]}"
unset SANITIZED_ARGS
