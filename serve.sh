#!/usr/bin/env bash
# Start a local vLLM (CPU) server with an OpenAI-compatible API on :${PORT}.
set -euo pipefail
cd "$(dirname "$0")"
source .venv/bin/activate

MODEL="${MODEL:-Qwen/Qwen2.5-1.5B-Instruct}"
PORT="${PORT:-8000}"
API_KEY="${VLLM_API_KEY:-dummy}"            # gateway requires a non-empty key
export VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-8}"   # GB of RAM for KV cache

exec vllm serve "$MODEL" \
  --port "$PORT" \
  --api-key "$API_KEY" \
  --dtype float16 \
  --max-model-len "${MAX_MODEL_LEN:-4096}"
