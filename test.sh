#!/usr/bin/env bash
# Smoke-test the local vLLM server.
set -euo pipefail
PORT="${PORT:-8000}"
API_KEY="${VLLM_API_KEY:-dummy}"
MODEL="${MODEL:-Qwen/Qwen2.5-1.5B-Instruct}"

echo "== models"
curl -sf "http://localhost:$PORT/v1/models" -H "Authorization: Bearer $API_KEY"
echo; echo "== chat"
curl -sf "http://localhost:$PORT/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one sentence.\"}]}"
echo
