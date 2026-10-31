#!/usr/bin/env bash
# Smoke-test a running vLLM server: list models, chat, tool call.
#   ./test.sh [config]     PORT=8001 ./test.sh   # PORT overrides the config's port
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-configs/qwen-1.5b.yaml}"
cfg() { awk -v k="$1" -F': *' '$1==k {sub(/ *#.*/,"",$2); print $2}' "$CONFIG"; }
MODEL="$(cfg model)"
PORT="${PORT:-$(cfg port)}"
API_KEY="$(cfg api-key)"
URL="http://localhost:$PORT/v1"
H=(-H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json')
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== models ($URL)"
curl -sf "$URL/models" "${H[@]}" | grep -q "\"$MODEL\"" || fail "$MODEL not served"
echo "ok: $MODEL"

echo "== chat"
out=$(curl -sf "$URL/chat/completions" "${H[@]}" -d "{\"model\":\"$MODEL\",\"max_tokens\":64,
  \"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one sentence.\"}]}") || fail "chat request"
grep -q '"finish_reason"' <<<"$out" || fail "chat: $out"
echo "ok: $(grep -o '"content":"[^"]*"' <<<"$out" | head -1)"

echo "== tool call"
out=$(curl -sf "$URL/chat/completions" "${H[@]}" -d "{\"model\":\"$MODEL\",\"max_tokens\":128,
  \"messages\":[{\"role\":\"user\",\"content\":\"What is the weather in Paris?\"}],
  \"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"description\":\"Get current weather for a city\",
    \"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}}}],
  \"tool_choice\":\"auto\"}") || fail "tool request"
grep -q '"name":"get_weather"' <<<"$out" || fail "no tool call: $out"
echo "ok: $(grep -o '"arguments":"[^}]*}' <<<"$out" | head -1)"

echo "All checks passed."
