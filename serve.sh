#!/usr/bin/env bash
# Start a vLLM server from a model config (Mac or Linux; Docker/k8s start vLLM themselves).
#   ./serve.sh configs/mac/qwen2.5-1.5b.yaml
#   ./serve.sh configs/nvidia/qwen3-8b.yaml --port 9000     # extra vllm flags override the config
#   ./serve.sh                                               # default model for this machine
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -gt 0 && "$1" != -* ]]; then
  CONFIG="$1"; shift
elif [[ "$(uname -s)" == Darwin ]]; then
  CONFIG=configs/mac/qwen2.5-1.5b.yaml
else
  CONFIG=configs/nvidia/qwen2.5-1.5b.yaml
fi
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
[[ -d .venv ]] || { echo "Not installed yet - run ./setup.sh first" >&2; exit 1; }

source .venv/bin/activate
echo "Starting $(grep -m1 '^model:' "$CONFIG") from $CONFIG"
exec vllm serve --config "$CONFIG" "$@"
