#!/usr/bin/env bash
# Start a local vLLM (CPU) server from a model config.
#   ./serve.sh                              # default: configs/qwen-1.5b.yaml
#   ./serve.sh configs/qwen-7b.yaml
#   ./serve.sh configs/qwen-7b.yaml --port 8001   # extra flags override the config
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-configs/qwen-1.5b.yaml}"
[[ $# -gt 0 ]] && shift
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
[[ -d .venv ]] || { echo "Not installed yet - run ./setup.sh first" >&2; exit 1; }

source .venv/bin/activate
exec vllm serve --config "$CONFIG" "$@"
