#!/usr/bin/env bash
# One-time install of vLLM into ./.venv. Safe to re-run.
#   Mac (Apple Silicon): prebuilt vLLM + vllm-metal plugin (Metal GPU via MLX), ~1-2 min
#   Linux + NVIDIA GPU:  pip install vllm (CUDA)
set -euo pipefail
cd "$(dirname "$0")"

VLLM_VERSION="0.32.0"
VLLM_METAL_VERSION="0.32.0"   # vllm-metal releases pin a matching vLLM version

die() { echo "ERROR: $*" >&2; exit 1; }

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64) PLATFORM=mac ;;
  Linux/x86_64|Linux/aarch64)
    command -v nvidia-smi >/dev/null || die "No NVIDIA GPU found (nvidia-smi missing). Linux setup needs an NVIDIA GPU + driver."
    PLATFORM=nvidia ;;
  *) die "Unsupported system $(uname -s)/$(uname -m). Use an Apple Silicon Mac or Linux with an NVIDIA GPU (or the docker/ or k8s/ setup)." ;;
esac
echo "Platform: $PLATFORM"

if ! command -v uv >/dev/null; then
  echo "Installing uv..."
  if [[ $PLATFORM == mac ]]; then
    brew install uv
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

[[ -d .venv ]] || uv venv --python 3.12 --seed
source .venv/bin/activate

if [[ $PLATFORM == mac ]]; then
  [[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 15 ]] || die "vllm-metal needs macOS 15 (Sequoia) or later."
  uv pip install \
    "https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}%2Bcpu-cp38-abi3-macosx_11_0_arm64.whl" \
    "https://github.com/vllm-project/vllm-metal/releases/download/v${VLLM_METAL_VERSION}/vllm_metal-${VLLM_METAL_VERSION}-cp312-cp312-macosx_15_0_arm64.whl"
else
  uv pip install "vllm==${VLLM_VERSION}"
fi

# Run from / so nothing in this folder can shadow the installed package.
(cd / && python -c "import vllm; print('vLLM', vllm.__version__, 'installed')")
if [[ $PLATFORM == mac ]]; then
  (cd / && python -c "import vllm_metal; print('vllm-metal installed')")
fi

echo "Done. Check a model:  ./test-model.sh configs/$PLATFORM/qwen2.5-1.5b.yaml"
echo "     Or run one:       ./serve.sh configs/$PLATFORM/qwen2.5-1.5b.yaml"
