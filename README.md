# vllm-local

Local vLLM (CPU build) on Apple Silicon, serving an OpenAI-compatible API for the LLM Gateway.

- vLLM **v0.32.0**, built from source (macOS has no prebuilt wheels; CPU only, FP16/FP32)
- API: `http://localhost:8000/v1`, key `dummy`
- Tool calling enabled (Qwen `hermes` parser)

## Requirements

- Apple Silicon Mac (M1-M4), macOS Sonoma or later
- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew (used to install `uv` if missing)
- ~5 GB free disk (+ model size), internet access

On Linux + NVIDIA none of this is needed: `pip install vllm` and use the configs as-is.

## Quick start

```bash
./setup.sh                          # one time, ~15-20 min (builds vLLM)
./serve.sh                          # starts the default model (configs/qwen-1.5b.yaml)
./test.sh                           # in another terminal: models + chat + tool call
```

## Models

Each model has its own config in `configs/`:

| Config | Model | Context | Speed (M4 Pro) |
|---|---|---|---|
| `qwen-1.5b.yaml` (default) | Qwen/Qwen2.5-1.5B-Instruct | 4096 | ~23 tok/s (measured) |
| `qwen-3b.yaml` | Qwen/Qwen2.5-3B-Instruct | 8192 | ~10-12 tok/s (est.) |
| `qwen-7b.yaml` | Qwen/Qwen2.5-7B-Instruct | 8192 | ~4-5 tok/s (est.) |

```bash
./serve.sh configs/qwen-7b.yaml                 # switch model (stop the old server first)
./test.sh configs/qwen-7b.yaml
./serve.sh configs/qwen-7b.yaml --port 8001     # extra vllm serve flags override the config
PORT=8001 ./test.sh configs/qwen-7b.yaml
```

Weights download from Hugging Face on first start (cached in `~/.cache/huggingface`).

### Adding a model

Copy a config and change `model`. Also check:

- `tool-call-parser` matches the model family (`hermes` for Qwen2.5, `llama3_json` for Llama 3, `mistral` for Mistral; see `vllm serve --help=all`)
- `max-model-len` fits the model's context window
- Use `-Instruct` models with safetensors weights (GGUF / AWQ / GPTQ don't work on Mac CPU)
- Gated models (e.g. Meta Llama) need `export HF_TOKEN=...` after accepting the license on Hugging Face

The gateway must use the exact `model` string from the config.

## Patch: `patches/0001-cpu-slot-mapping-signature.patch`

Applied automatically by `setup.sh`. v0.32.0 crashes on the first request on macOS CPU with
`RuntimeError: Boolean value of Tensor with more than one value is ambiguous`.
The CPU fallback `_compute_slot_mapping_kernel_impl` (vllm/utils/cpu_triton_utils.py) still has the
old signature (`block_size`, `BLOCKS_PER_KV_BLOCK`) while the Triton kernel it replaces dropped them, and
the dispatcher maps args by position, so everything after `block_table_stride` shifts by one. The patch
realigns the signature and pads unused slots with `PAD_ID` like the Triton kernel does.
Drop it once upstream fixes this.

## Uninstall

```bash
pkill -f "vllm serve"
rm -rf .venv vllm ~/.cache/huggingface/hub/models--Qwen--* ~/.cache/vllm
```

## Notes

- No Metal/GPU in this build. For GPU on Mac see [vllm-metal](https://github.com/vllm-project/vllm-metal).
- Keep models small (0.5B-7B) for usable speed on CPU.
