#!/usr/bin/env bash
# One-time install: Python 3.12 venv + vLLM built from source for macOS CPU (Apple Silicon).
# Safe to re-run; skips steps that are already done. First run takes ~15-20 min.
set -euo pipefail
cd "$(dirname "$0")"

VLLM_VERSION="v0.32.0"

[[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]] || {
  echo "This setup is for Apple Silicon Macs. On Linux + NVIDIA just: pip install vllm" >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "Install Xcode Command Line Tools: xcode-select --install" >&2; exit 1; }
command -v uv >/dev/null || { echo "Installing uv..."; brew install uv; }

[[ -d .venv ]] || uv venv --python 3.12 --seed
source .venv/bin/activate

if [[ ! -d vllm ]]; then
  git clone --depth 1 --branch "$VLLM_VERSION" https://github.com/vllm-project/vllm.git
fi

echo "Applying patches..."
for p in patches/*.patch; do
  if git -C vllm apply --reverse --check "../$p" 2>/dev/null; then
    echo "  already applied: $p"
  else
    git -C vllm apply "../$p" && echo "  applied: $p"
  fi
done

echo "Installing dependencies..."
(cd vllm && uv pip install -r requirements/cpu.txt)

echo "Building vLLM (this is the slow part)..."
# The patch makes the tree "dirty", which would version the build as 0.32.1.devN; pin it.
(cd vllm && SETUPTOOLS_SCM_PRETEND_VERSION="${VLLM_VERSION#v}" uv pip install -e .)

# Run from / so the vllm/ source folder here doesn't shadow the installed package.
(cd / && python -c "import vllm; print('vLLM', vllm.__version__, 'installed')")
echo "Done. Next: ./serve.sh   then in another terminal: ./test.sh"
