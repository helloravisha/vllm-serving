# vllm-local

Local vLLM (CPU build) on Apple Silicon, serving an OpenAI-compatible API for the LLM Gateway.

- vLLM **v0.32.0**, built from source (macOS has no prebuilt wheels; CPU only, FP16/FP32)
- Default model: `Qwen/Qwen2.5-1.5B-Instruct`
- API: `http://localhost:8000/v1`, key `dummy`

## Setup (one time)

```bash
brew install uv
uv venv --python 3.12 --seed
source .venv/bin/activate
git clone --depth 1 --branch v0.32.0 https://github.com/vllm-project/vllm.git
cd vllm
git apply ../patches/0001-cpu-slot-mapping-signature.patch   # required, see below
uv pip install -r requirements/cpu.txt
uv pip install -e .        # ~10-20 min
```

## Run

```bash
./serve.sh                 # start the server
./test.sh                  # smoke test: list models + one chat request
```

Overrides via env vars: `MODEL`, `PORT`, `VLLM_API_KEY`, `VLLM_CPU_KVCACHE_SPACE` (GB), `MAX_MODEL_LEN`.

## Patch: `patches/0001-cpu-slot-mapping-signature.patch`

v0.32.0 crashes on the first request on macOS CPU with
`RuntimeError: Boolean value of Tensor with more than one value is ambiguous`.
The CPU fallback `_compute_slot_mapping_kernel_impl` (vllm/utils/cpu_triton_utils.py) still has the
old signature (`block_size`, `BLOCKS_PER_KV_BLOCK`) while the Triton kernel it replaces dropped them, and
the dispatcher maps args by position, so everything after `block_table_stride` shifts by one. The patch
realigns the signature and pads unused slots with `PAD_ID` like the Triton kernel does.
Drop it once upstream fixes this.

## Performance (M4 Pro, 48 GB)

Qwen2.5-1.5B-Instruct, FP16: ~23 tokens/s for a single request.

## Notes

- No Metal/GPU in this build. For GPU on Mac see [vllm-metal](https://github.com/vllm-project/vllm-metal).
- Keep models small (0.5B-3B) for usable speed on CPU.
