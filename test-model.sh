#!/usr/bin/env bash
# Full check of one model: start its server (downloading the model if needed), wait until ready,
# run test.sh, stop the server, print PASS/FAIL. Exit code 0 = pass, 1 = fail.
#   ./test-model.sh configs/mac/qwen3-8b.yaml
#   ./test-model.sh configs/mac/qwen3-8b.yaml --cleanup-after   # delete the model's files afterwards
#   ./test-model.sh configs/mac/qwen3-8b.yaml --port 9002       # use another port
# Several models:
#   for c in configs/mac/qwen3-8b.yaml configs/mac/bge-m3.yaml; do ./test-model.sh "$c"; done
set -uo pipefail
cd "$(dirname "$0")"

CONFIG="" CLEANUP=0 PORT_OVERRIDE="" TIMEOUT_MIN="${TIMEOUT_MIN:-60}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup-after) CLEANUP=1 ;;
    --port) PORT_OVERRIDE="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option $1" >&2; exit 1 ;;
    *) CONFIG="$1" ;;
  esac
  shift
done
[[ -n "$CONFIG" ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
[[ -d .venv ]] || { echo "Not installed yet - run ./setup.sh first" >&2; exit 1; }

field() { awk -F': *' -v k="$1" '$1==k {sub(/ *#.*/, "", $2); print $2; exit}' "$CONFIG"; }
NAME=$(basename "$CONFIG" .yaml)
CKPT=$(field model)
SERVED=$(field served-model-name); SERVED=${SERVED:-$CKPT}
PORT=${PORT_OVERRIDE:-$(field port)}
LOG="logs/$NAME.log"
mkdir -p logs

elapsed() { local s=$(( $(date +%s) - $1 )); [[ $s -ge 60 ]] && printf "%dm %02ds" $((s / 60)) $((s % 60)) || printf "%ds" "$s"; }
hf_size() { .venv/bin/hf cache ls --json 2>/dev/null | python3 -c '
import json, sys
print(next((r["size"] + "B" for r in json.load(sys.stdin) if r["repo_id"] == sys.argv[1]), ""))' "$1"; }

echo "▶ $NAME  ($SERVED, port $PORT)"

if curl -s -m 2 -o /dev/null "http://localhost:$PORT/health"; then
  echo "  port $PORT is already in use (a server is running?). Stop it or use --port." >&2
  exit 1
fi

[[ -z "$(hf_size "$CKPT")" ]] && echo "  model not downloaded yet: downloading $CKPT (first time only)"

SERVER_PID=""
stop_server() {
  [[ -n "$SERVER_PID" ]] || return 0
  echo -n "  stopping server...           "
  kill "$SERVER_PID" 2>/dev/null
  for _ in $(seq 1 20); do kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 1; done
  kill -9 "$SERVER_PID" 2>/dev/null
  pkill -f "vllm serve --config $CONFIG" 2>/dev/null
  SERVER_PID=""
  echo "done"
}
trap 'echo; stop_server; echo "Interrupted."; exit 130' INT TERM

start=$(date +%s)
port_args=(); [[ -n "$PORT_OVERRIDE" ]] && port_args=(--port "$PORT_OVERRIDE")
./serve.sh "$CONFIG" ${port_args[@]+"${port_args[@]}"} > "$LOG" 2>&1 &
SERVER_PID=$!

echo -n "  starting server...           "
state=timeout
for _ in $(seq 1 $((TIMEOUT_MIN * 30))); do
  if grep -q "Application startup complete" "$LOG"; then state=up; break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then state=crashed; break; fi
  sleep 2
done
startup=$(elapsed "$start")

result=FAIL
case $state in
  up)
    echo "ready in $startup"
    test_start=$(date +%s)
    if URL="http://localhost:$PORT" ./test.sh "$CONFIG"; then result=PASS; fi
    test_time=$(elapsed "$test_start")
    ;;
  crashed)
    echo "crashed after $startup"
    echo "  last lines of the server log:"
    grep -vE "ulimit|^\s*$" "$LOG" | tail -5 | sed 's/^/    /'
    result="SERVER FAILED TO START"
    ;;
  timeout)
    echo "not ready after $TIMEOUT_MIN min (raise with TIMEOUT_MIN=...)"
    result="SERVER FAILED TO START"
    ;;
esac
stop_server
trap - INT TERM

echo
if [[ $result == PASS ]]; then
  echo "✅ $NAME: PASS   (startup $startup, test $test_time)"
else
  echo "❌ $NAME: $result"
fi
echo "   server log: $LOG"

if [[ $CLEANUP -eq 1 ]]; then
  size=$(hf_size "$CKPT")
  if [[ -n "$size" ]] && .venv/bin/hf cache rm "model/$CKPT" -y >/dev/null 2>&1; then
    echo "  cleanup: deleted $CKPT model files ($size freed)"
  fi
fi

[[ $result == PASS ]]
