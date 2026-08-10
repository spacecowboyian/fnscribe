#!/bin/zsh -l
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is not set. Add it to .env or export it before running."
  exit 1
fi

export FNSCRIBE_PROJECT_ROOT="$ROOT"
export FNSCRIBE_HOME="${FNSCRIBE_HOME:-$ROOT/work/fn-scribe-store}"
export FNSCRIBE_TRIGGER="${FNSCRIBE_TRIGGER:-fn}"
export FNSCRIBE_PLACEHOLDER="${FNSCRIBE_PLACEHOLDER:-transcribing...}"
export FNSCRIBE_HISTORY_LIMIT="${FNSCRIBE_HISTORY_LIMIT:-50}"
export FNSCRIBE_SOUND="${FNSCRIBE_SOUND:-1}"
export FNSCRIBE_START_SOUND="${FNSCRIBE_START_SOUND:-Ping}"
export FNSCRIBE_STOP_SOUND="${FNSCRIBE_STOP_SOUND:-Pop}"
export FNSCRIBE_COMPLETE_SOUND="${FNSCRIBE_COMPLETE_SOUND:-Glass}"
export OPENAI_TRANSCRIBE_MODEL="${OPENAI_TRANSCRIBE_MODEL:-gpt-4o-mini-transcribe}"
export OPENAI_CLEANUP_MODEL="${OPENAI_CLEANUP_MODEL:-gpt-5-mini}"
export FNSCRIBE_CLEANUP_MODE="${FNSCRIBE_CLEANUP_MODE:-auto}"
export FNSCRIBE_UI_PORT="${FNSCRIBE_UI_PORT:-8765}"

if [[ ! -x "$ROOT/work/bin/fn-scribe" ]]; then
  "$ROOT/scripts/build.sh"
fi

python3 -m http.server "$FNSCRIBE_UI_PORT" --bind 127.0.0.1 --directory "$ROOT/public" >> "$ROOT/work/fn-scribe-ui.log" 2>&1 &
ui_pid=$!
trap 'kill "$ui_pid" 2>/dev/null || true' EXIT

sleep 0.4
open "http://127.0.0.1:$FNSCRIBE_UI_PORT/fn-scribe-history.html" >/dev/null 2>&1 || true

exec "$ROOT/work/bin/fn-scribe"
