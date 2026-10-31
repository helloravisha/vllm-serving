# llm-serving

Self-hosted LLMs behind an OpenAI-compatible API, using [vLLM](https://github.com/vllm-project/vllm) **v0.32.0**.
One set of model configs, four ways to run them:

| Flavour | Hardware | Install | Start | Configs |
|---|---|---|---|---|
| **Mac** | Apple Silicon GPU (Metal, via [vllm-metal](https://github.com/vllm-project/vllm-metal)) | `./setup.sh` | `./serve.sh` | `configs/mac/` |
| **Linux** | NVIDIA GPU (CUDA) | `./setup.sh` | `./serve.sh` | `configs/nvidia/` |
| **Docker** | NVIDIA GPU | — | `docker compose up` | `configs/nvidia/` |
| **Kubernetes** (GKE) | NVIDIA GPU nodes | — | `kubectl apply` | `configs/nvidia/` |

Every server speaks the same API (`/v1/chat/completions`, `/v1/embeddings`, `/rerank`), so clients and the
LLM Gateway only need the server's address, API key and model id.

## Layout

```
setup.sh      install vLLM into .venv (Mac: vllm + vllm-metal, Linux: pip install vllm)
serve.sh      start one model:            ./serve.sh configs/<mac|nvidia>/<model>.yaml
test.sh       check a running server:     ./test.sh configs/<mac|nvidia>/<model>.yaml
status.sh     what's running + disk used (read-only)
PENDING.md    open items (unverified parts, known limitations, to-dos)
cleanup.sh    free disk space (asks first)
configs/mac/      one file per model, tuned for Apple Silicon
configs/nvidia/   same models, tuned for NVIDIA GPUs (Linux, Docker, Kubernetes)
docker/       docker-compose.yml (one service per model) + .env.example
k8s/          example deployment for one model on GKE
```

## Models

One config per model, same file name, port and model id on both hardware types.
Ports group by type: 800x chat, 801x reasoning, 802x decision, 803x embedding/reranker.

| Config | Model id (what clients send) | Type | Port | Mac tested |
|---|---|---|---|---|
| `qwen2.5-1.5b` | Qwen/Qwen2.5-1.5B-Instruct | chat + tools | 8000 | ✅ chat, tools |
| `qwen2.5-7b` | Qwen/Qwen2.5-7B-Instruct | chat + tools | 8001 | ✅ chat, tools |
| `qwen3-8b` | Qwen/Qwen3-8B | chat + tools + thinking | 8002 | ✅ chat, tools, thinking |
| `llama3.1-8b` | meta-llama/Llama-3.1-8B-Instruct | chat + tools | 8003 | ✅ chat, tools |
| `mistral-7b` | mistralai/Mistral-7B-Instruct-v0.3 | chat + tools | 8004 | ✅ chat, tools (see note) |
| `phi4-mini` | microsoft/Phi-4-mini-instruct | chat | 8005 | ✅ chat |
| `gemma3-12b` | google/gemma-3-12b-it | chat | 8006 | ✅ chat |
| `gpt-oss-20b` | openai/gpt-oss-20b | chat + tools + thinking | 8007 | ✅ chat, tools, thinking |
| `deepseek-r1-qwen-7b` | deepseek-ai/DeepSeek-R1-Distill-Qwen-7B | reasoning | 8010 | ✅ chat, reasoning |
| `qwen3-0.6b-decider` | Qwen/Qwen3-0.6B | decision | 8020 | ✅ structured choice |
| `lfm2.5-1.2b-decider` | LiquidAI/LFM2.5-1.2B-Instruct | decision | 8021 | ✅ structured choice |
| `qwen3-embedding-0.6b` | Qwen/Qwen3-Embedding-0.6B | embedding | 8030 | ✅ embeddings |
| `bge-m3` | BAAI/bge-m3 | embedding | 8031 | ✅ embeddings |
| `qwen3-reranker-0.6b` | Qwen/Qwen3-Reranker-0.6B | reranker | 8032 | ✅ ranking (see note) |

All 14 models pass `./test.sh` on Mac. Notes from testing (2026-10-31, M4 Pro):
- `mistral-7b` on Mac loads the official `mistralai` tokenizer (`tokenizer` + `tokenizer-mode: mistral`);
  with the MLX copy's tokenizer, tool calls came back as plain text.
- `phi4-mini` is chat-only: its tool calling needs `examples/tool_chat_template_phi4_mini.jinja` from the vLLM
  source repo, which the package doesn't ship.
- `qwen3-reranker-0.6b` ranks correctly but scores are compressed (an unrelated document still scored 0.79);
  Qwen3-Reranker works best with its instruction prompt format. Compare scores relative to each other.
- Thinking models (`qwen3-8b`, `gpt-oss-20b`, `deepseek-r1-qwen-7b`) spend tokens reasoning first, so give them
  a generous `max_tokens`.

The NVIDIA configs have not been run yet (no NVIDIA hardware was available); run `./test.sh` the first time.

On Mac, several configs load a smaller 4-bit MLX copy of the model (e.g. `mlx-community/Qwen3-8B-4bit`) but
`served-model-name` keeps the id the same as on NVIDIA, so clients never need to know which hardware answered.

**Gated models:** Llama and Gemma weights on NVIDIA need a Hugging Face token with the license accepted
on the model page (`hf auth login`, or `HF_TOKEN` for Docker/Kubernetes). The Mac configs use ungated mirrors.

### Adding a model

1. Copy a config in `configs/mac/` and `configs/nvidia/` and change `model`, `served-model-name`, `port`.
2. Set the `# type:` line (`chat`, `reasoning`, `decision`, `embed`, `rerank`); `test.sh` uses it.
3. Pick the tool parser for the family (`hermes` Qwen, `llama3_json` Llama, `mistral` Mistral, ...; see
   `vllm serve --help=all`) and a `max-model-len` within the model's context window.
4. For Docker, add a service block to `docker/docker-compose.yml`.
5. Start it and run `./test.sh` on it.

## Mac

Requirements: Apple Silicon, macOS 15+, Homebrew. Speed (M4 Pro, Qwen2.5-1.5B): ~41 tok/s single request,
~125 tok/s total with 4 parallel requests.

```bash
./setup.sh                                   # ~1-2 min, prebuilt packages
./serve.sh configs/mac/qwen2.5-1.5b.yaml     # first start downloads the model
./test.sh  configs/mac/qwen2.5-1.5b.yaml     # in another terminal
```

Mac memory is shared with your apps: `gpu-memory-utilization` in each config is kept low (0.2-0.5).
Run two or three models at a time at most. API key on Mac is `dummy`; servers listen on 127.0.0.1 only.

## Linux (NVIDIA)

Requirements: NVIDIA GPU + driver (`nvidia-smi` works), internet access.

```bash
export VLLM_API_KEY=<choose-a-key>           # NVIDIA configs take the key from the environment
./setup.sh                                   # pip install vllm==0.32.0 into .venv
./serve.sh configs/nvidia/qwen3-8b.yaml
./test.sh  configs/nvidia/qwen3-8b.yaml
```

## Docker (NVIDIA)

Requirements: Docker + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/).

```bash
cd docker
cp .env.example .env                         # set VLLM_API_KEY (and HF_TOKEN for Llama/Gemma)
docker compose up -d qwen3-8b                # nothing starts unless you name a service
docker compose logs -f qwen3-8b
VLLM_API_KEY=<key> ../test.sh ../configs/nvidia/qwen3-8b.yaml
docker compose down
```

This is the same image Kubernetes uses, so it is a good way to check a model before deploying it.

## Kubernetes (GKE)

`k8s/` deploys **Qwen3-8B on one NVIDIA L4** as a template. Requirements: a GKE cluster with a GPU node pool
(`nvidia-l4`, drivers installed by GKE) and GPU quota in the region.

```bash
kubectl create secret generic vllm-secrets --from-literal=api-key=<key> --from-literal=hf-token=<token>
kubectl apply -f k8s/pvc.yaml -f k8s/configmap.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl rollout status deploy/vllm-qwen3-8b --timeout=20m
kubectl port-forward svc/vllm-qwen3-8b 8002:8002 &
VLLM_API_KEY=<key> ./test.sh configs/nvidia/qwen3-8b.yaml
```

The gateway (in-cluster) uses `http://vllm-qwen3-8b.<namespace>.svc.cluster.local:8002/v1`.
For another model: copy the k8s files, rename `qwen3-8b`, paste its `configs/nvidia/*.yaml` into the
ConfigMap, change the port, and pick a GPU type that fits (L4 24 GB for up to ~8B, A100/H100 for larger).
The manifests are schema-validated but have not been applied to a real cluster yet.

## Status and cleanup

```bash
./status.sh                         # servers, downloaded models, disk used
./cleanup.sh --models               # delete model weights used by configs (re-download on next start)
./cleanup.sh --models qwen3-8b      # just one model
./cleanup.sh --env                  # delete .venv (./setup.sh recreates it)
./cleanup.sh --caches               # vLLM/uv caches + incomplete HF downloads
./cleanup.sh --docker               # vLLM containers, image and model volume
./cleanup.sh --all
```

Model weights live in the shared Hugging Face cache (`~/.cache/huggingface`); cleanup only removes models
named in `configs/`, using `hf cache rm` so shared files are freed correctly.
