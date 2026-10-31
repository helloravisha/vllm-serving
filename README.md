# vllm-serving

Run open AI models (Qwen, Llama, Mistral, Gemma, …) on your own hardware and call them through the same API as
OpenAI. Works on an Apple Silicon Mac for local testing and on NVIDIA GPUs (Linux, Docker, Kubernetes) for real
deployments.

**Contents:** [What is vLLM?](#what-is-vllm) · [What this repo gives you](#what-this-repo-gives-you) ·
[Quick start (Mac)](#quick-start-mac) · [Models](#models) · [Testing a model](#testing-a-model) ·
[Calling a model](#calling-a-model) · [Running on NVIDIA](#running-on-nvidia-linux-docker-kubernetes) ·
[Adding a model](#adding-a-model) · [Disk space](#disk-space-status-and-cleanup) ·
[Troubleshooting](#troubleshooting) · [Repo layout](#repo-layout)

---

## What is vLLM?

An AI model on its own is just a large file of numbers ("weights"). To use it you need software that loads it onto
a GPU, accepts requests, runs the model and sends back answers. That software is a **serving engine**.

**[vLLM](https://github.com/vllm-project/vllm)** is a high-throughput, memory-efficient serving engine for running
open models (Llama, Mistral, Qwen, …) in production, and the most widely used open-source one. A basic model
runner, such as a simple Hugging Face script, wastes a lot of GPU memory and handles users one at a time; vLLM is
built to serve many users at once, quickly and at low cost.

```
your app ──HTTP──▶  vLLM server  ──▶  model on the GPU
            ◀── answer ──┘
```

### The problem vLLM solves

While a model writes an answer, the GPU keeps a **KV cache** for every request: the model's working memory of that
conversation so far. With many users at once, there is one KV cache per user, and these take up most of the GPU
memory that isn't used by the model itself.

Before vLLM, serving engines handled this memory badly:

- **Reserved too much up front.** Each request got one large, continuous block of memory sized for the *longest
  possible* conversation, even if the user only asked a short question.
- **Wasted most of it.** The vLLM authors measured that existing systems wasted **60–80% of the memory reserved
  for KV caches**, sitting empty or fragmented. Less usable memory means fewer users served at the same time.

### How vLLM fixes it: PagedAttention

vLLM's key idea, **PagedAttention**, borrows from how operating systems manage RAM with *virtual memory* and
*paging* (the idea behind the project's name):

- Instead of one large continuous block per conversation, the KV cache is split into small, fixed-size **pages**.
- Pages can sit anywhere in GPU memory, not side by side, and are **allocated as each new word is generated and
  freed** as soon as a request finishes.
- So memory is used only for text that actually exists. Waste drops to almost nothing, and the freed memory serves
  more users.

### Key benefits

- **High concurrency.** With almost no wasted memory, many more requests fit on the same GPU at the same time.
- **High throughput.** **Continuous batching** groups incoming requests together on the fly: a new request joins
  the batch as soon as there is room, instead of waiting for the current batch to finish, which keeps the GPU busy.
- **OpenAI-compatible API.** The server answers on the same endpoints and in the same format as OpenAI
  (`/v1/chat/completions`, `/v1/embeddings`, …). Any app or library that can call OpenAI can call vLLM by changing
  only the URL, and it plugs into LLM gateways such as LiteLLM or our own LLM Gateway.
- **Many models.** Most popular open model families work out of the box (Qwen, Llama, Mistral, Gemma, Phi,
  gpt-oss, DeepSeek, …), including chat, embedding and reranking models.
- **Runs in many places.** NVIDIA GPUs (main target), and Apple Silicon Macs through the
  [vllm-metal](https://github.com/vllm-project/vllm-metal) plugin.

**One vLLM server runs one model.** To offer several models you run several servers, each on its own port. This
repo gives every model its own config file and port for exactly that reason.

How it compares to tools you may know:

| | vLLM | Ollama | OpenAI / Anthropic API |
|---|---|---|---|
| Runs where | Your hardware | Your hardware | Their cloud |
| Built for | Production, many users | Personal/local use | Production |
| API | OpenAI-compatible | Own API (+ partial OpenAI) | Their own |
| Cost | Your hardware | Your hardware | Pay per token |

---

## What this repo gives you

- **One-command install** (`setup.sh`) for Mac and Linux.
- **14 ready-made model configs**: chat, tool calling, reasoning, decision, embedding and reranking models. Each
  exists twice: `configs/mac/` (Apple Silicon) and `configs/nvidia/` (NVIDIA GPUs), with the **same model name and
  port**, so code written against your Mac works unchanged against the cloud deployment.
- **Testing**: `test-model.sh` starts a model, checks it actually works for its type, stops it and prints PASS/FAIL.
- **Four ways to run**: Mac, Linux, Docker, Kubernetes (GKE).
- **Disk management**: `status.sh` shows what's using space, `cleanup.sh` frees it.

| Flavour | Hardware | Install | Start a model | Configs |
|---|---|---|---|---|
| **Mac** | Apple Silicon GPU (Metal) | `./setup.sh` | `./serve.sh` | `configs/mac/` |
| **Linux** | NVIDIA GPU | `./setup.sh` | `./serve.sh` | `configs/nvidia/` |
| **Docker** | NVIDIA GPU | – | `docker compose up` | `configs/nvidia/` |
| **Kubernetes** | NVIDIA GPU nodes (GKE) | – | `kubectl apply` | `configs/nvidia/` |

Everything uses vLLM **v0.32.0**.

---

## Quick start (Mac)

**You need:** an Apple Silicon Mac (M1–M4), macOS 15 or newer, [Homebrew](https://brew.sh), internet access and a
few GB of free disk. No Hugging Face account is needed for the Mac configs.

```bash
git clone https://github.com/helloravisha/vllm-serving.git && cd vllm-serving
./setup.sh                                        # installs vLLM into .venv (about 1 minute)
./test-model.sh configs/mac/qwen2.5-1.5b.yaml     # downloads a small model (3 GB) and checks it
```

You should see:

```
✅ qwen2.5-1.5b: PASS   (startup 46s, test 1s)
```

To keep a model running and use it:

```bash
./serve.sh configs/mac/qwen2.5-1.5b.yaml          # leave this terminal open; Ctrl+C stops it
```

It now answers at `http://localhost:8000/v1` with API key `dummy`. See [Calling a model](#calling-a-model).

---

## Models

All 14 configs pass `test-model.sh` on a Mac (M4 Pro, 48 GB, tested 2026-10-31). The NVIDIA versions have not been
run yet.

| Config | Model name (what you send) | Type | Port | Size (Mac) | Tested on Mac |
|---|---|---|---|---|---|
| `qwen2.5-1.5b` | `Qwen/Qwen2.5-1.5B-Instruct` | chat | 8000 | 3.1 GB | ✅ chat, tools |
| `qwen2.5-7b` | `Qwen/Qwen2.5-7B-Instruct` | chat | 8001 | 4.3 GB | ✅ chat, tools |
| `qwen3-8b` | `Qwen/Qwen3-8B` | chat + thinking | 8002 | 4.6 GB | ✅ chat, tools, thinking |
| `llama3.1-8b` | `meta-llama/Llama-3.1-8B-Instruct` | chat | 8003 | 4.5 GB | ✅ chat, tools |
| `mistral-7b` | `mistralai/Mistral-7B-Instruct-v0.3` | chat | 8004 | 4.1 GB | ✅ chat, tools |
| `phi4-mini` | `microsoft/Phi-4-mini-instruct` | chat | 8005 | 7.7 GB | ✅ chat (no tools) |
| `gemma3-12b` | `google/gemma-3-12b-it` | chat | 8006 | 8.1 GB | ✅ chat (no tools) |
| `gpt-oss-20b` | `openai/gpt-oss-20b` | chat + thinking | 8007 | 13.8 GB | ✅ chat, tools, thinking |
| `deepseek-r1-qwen-7b` | `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B` | reasoning | 8010 | 4.3 GB | ✅ reasoning |
| `qwen3-0.6b-decider` | `Qwen/Qwen3-0.6B` | decision | 8020 | 1.5 GB | ✅ structured choice |
| `lfm2.5-1.2b-decider` | `LiquidAI/LFM2.5-1.2B-Instruct` | decision | 8021 | 2.3 GB | ✅ structured choice |
| `qwen3-embedding-0.6b` | `Qwen/Qwen3-Embedding-0.6B` | embedding | 8030 | 0.6 GB | ✅ embeddings |
| `bge-m3` | `BAAI/bge-m3` | embedding | 8031 | 2.3 GB | ✅ embeddings |
| `qwen3-reranker-0.6b` | `Qwen/Qwen3-Reranker-0.6B` | reranker | 8032 | 0.6 GB | ✅ ranking |

**What the types mean:**

| Type | What it does | Example use |
|---|---|---|
| **chat** | Answers in text. Most can also **call tools**: instead of answering, they reply with which function your app should run and with what arguments | Assistants, summarising, planning which tools to call |
| **thinking / reasoning** | Thinks step by step before answering; the thinking comes back in a separate `reasoning` field | Harder questions, maths, multi-step problems |
| **decision** | Small, fast model whose answer is forced to be one of a fixed list of options | Routing ("is this code, chat or research?") |
| **embedding** | Turns text into a list of numbers that represents its meaning; similar texts get similar numbers | Search by meaning, RAG, finding duplicates |
| **reranker** | Scores documents for how well they answer a question | Picking the best results after a search |

**Ports** group by type: `800x` chat, `801x` reasoning, `802x` decision, `803x` embedding/reranker.

**Notes:**
- **Mac uses smaller copies of some models.** Several Mac configs load a 4-bit version (e.g.
  `mlx-community/Qwen3-8B-4bit`) to save memory, but they answer under the same model name as NVIDIA, so your code
  never needs to know which hardware answered.
- **Thinking models** (`qwen3-8b`, `gpt-oss-20b`, `deepseek-r1-qwen-7b`) think before answering. Give them a generous
  `max_tokens` (e.g. 2000+), or the limit can be used up before the answer appears.
- **`phi4-mini` and `gemma3-12b` don't have tool calling configured**; use them for plain chat.
- **Decision models** always answer with one of your options, but not always the right one (4 of 6 correct in a
  quick check). See [Decision](#decision-answer-forced-to-a-fixed-list).
- **`qwen3-reranker-0.6b`** puts results in the right order, but its scores sit close together (an unrelated
  document still scored 0.79). Compare scores with each other, not against a fixed threshold.
- **Gated models on NVIDIA:** the original Llama and Gemma weights need a free Hugging Face token and accepting
  the license on the model page. The Mac configs use copies that don't.

More open items: [PENDING.md](PENDING.md).

---

## Testing a model

### Automatic check (recommended)

```bash
./test-model.sh configs/mac/qwen3-8b.yaml
```

This starts the model's server (downloading the model the first time), waits until it's ready, runs checks for its
type, stops the server and prints the result. Exit code is 0 on pass, 1 on fail, so it also works in scripts.

```
▶ qwen3-8b  (Qwen/Qwen3-8B, port 8002)
  starting server...           ready in 2m 03s
== configs/mac/qwen3-8b.yaml  [chat]  Qwen/Qwen3-8B @ http://localhost:8002
ok:   model listed
ok:   chat -> '42'
ok:   reasoning field present (412 chars)
ok:   tool call -> get_weather({"city": "Paris"})
All checks passed.
  stopping server...           done

✅ qwen3-8b: PASS   (startup 2m 03s, test 9s)
   server log: logs/qwen3-8b.log
```

What gets checked:

| Type | Checks |
|---|---|
| chat | Answers a question; calls a tool correctly (if tool calling is enabled) |
| reasoning | Answers; thinking is returned separately |
| decision | Answer is one of the allowed options |
| embedding | Similar sentences score closer than unrelated ones |
| reranker | Relevant documents rank above an unrelated one |

Options:

```bash
./test-model.sh configs/mac/qwen3-8b.yaml --cleanup-after   # delete the model's files afterwards
./test-model.sh configs/mac/qwen3-8b.yaml --port 9002       # use another port if 8002 is busy

# test several, one after another
for c in configs/mac/qwen2.5-1.5b.yaml configs/mac/bge-m3.yaml; do ./test-model.sh "$c"; done

# test all 14 (~65 GB of downloads; --cleanup-after means you only need room for one model at a time)
for c in configs/mac/*.yaml; do ./test-model.sh "$c" --cleanup-after; done
```

### Checking a server that's already running

If you started a model with `serve.sh` (or it runs in Docker or Kubernetes), run only the checks:

```bash
./test.sh configs/mac/qwen3-8b.yaml
URL=http://my-server:8002 VLLM_API_KEY=<key> ./test.sh configs/nvidia/qwen3-8b.yaml   # a remote server
```

---

## Calling a model

Start the model first (`./serve.sh configs/mac/<model>.yaml`). Everything you need is in its config file:

- **Address:** `http://localhost:<port>/v1`, where port is the `port:` line
- **Model name:** the `served-model-name:` line
- **API key:** `dummy` on Mac (NVIDIA uses the `VLLM_API_KEY` you set)

The examples use `qwen2.5-1.5b` (port 8000) unless noted. The Python examples use the standard
[`openai`](https://pypi.org/project/openai/) library (`pip install openai`).

### Chat

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer dummy" -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-1.5B-Instruct",
       "messages": [{"role": "user", "content": "Explain RAG in two sentences."}]}'
```

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1", api_key="dummy")
reply = client.chat.completions.create(
    model="Qwen/Qwen2.5-1.5B-Instruct",
    messages=[{"role": "user", "content": "Explain RAG in two sentences."}],
)
print(reply.choices[0].message.content)
```

Add `"stream": true` (Python: `stream=True`) to receive the answer word by word.

### Tool calling

You describe the tools; the model replies with which one to call and the arguments. **Your app runs the tool**,
then sends the result back for the final answer.

```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather for a city",
        "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]},
    },
}]
reply = client.chat.completions.create(
    model="Qwen/Qwen2.5-1.5B-Instruct",
    messages=[{"role": "user", "content": "What is the weather in Paris?"}],
    tools=tools,
)
call = reply.choices[0].message.tool_calls[0]
print(call.function.name, call.function.arguments)   # get_weather {"city": "Paris"}
```

Works on: `qwen2.5-1.5b`, `qwen2.5-7b`, `qwen3-8b`, `llama3.1-8b`, `mistral-7b`, `gpt-oss-20b`.

### Thinking / reasoning models

The answer is in `content`; the model's thinking is in a separate `reasoning` field.

```python
client = OpenAI(base_url="http://localhost:8002/v1", api_key="dummy")      # qwen3-8b
reply = client.chat.completions.create(
    model="Qwen/Qwen3-8B",
    messages=[{"role": "user", "content": "What is 17 * 23?"}],
    max_tokens=2000,
)
message = reply.choices[0].message
print("answer:", message.content)
print("thinking:", getattr(message, "reasoning", None))
```

To skip thinking on Qwen3 for a faster answer, add `extra_body={"chat_template_kwargs": {"enable_thinking": False}}`.

### Decision (answer forced to a fixed list)

```python
client = OpenAI(base_url="http://localhost:8020/v1", api_key="dummy")      # qwen3-0.6b-decider
reply = client.chat.completions.create(
    model="Qwen/Qwen3-0.6B",
    messages=[{"role": "user", "content":
               "Route this request: 'Write a Python function that reverses a list.' Answer with one of: code, chat, research."}],
    max_tokens=10,
    temperature=0,                                                         # same input, same answer
    extra_body={
        "structured_outputs": {"choice": ["code", "chat", "research"]},   # answer must be one of these
        "chat_template_kwargs": {"enable_thinking": False},
    },
)
print(reply.choices[0].message.content)   # code
```

**Valid isn't the same as right.** `structured_outputs` guarantees the answer is one of your options, not that it's
the correct one. In a quick check, `qwen3-0.6b-decider` routed 4 of 6 sample requests correctly: it handled code and
research requests but sent "Hi, how are you today?" to `code`. Small models are also sensitive to wording:
"Answer with code, chat or research." gave `research` for the request above. Before relying on a decision model,
test it on 20–50 of your real requests, try few-shot examples in the prompt, or use a larger model.

### Embeddings

```python
client = OpenAI(base_url="http://localhost:8030/v1", api_key="dummy")      # qwen3-embedding-0.6b
result = client.embeddings.create(
    model="Qwen/Qwen3-Embedding-0.6B",
    input=["How do I reset my password?", "I forgot my login"],
)
print(len(result.data), "vectors of", len(result.data[0].embedding), "numbers")
```

### Reranking

Not part of the OpenAI API, so call it directly:

```bash
curl http://localhost:8032/rerank \
  -H "Authorization: Bearer dummy" -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-Reranker-0.6B",
       "query": "What is the capital of France?",
       "documents": ["Paris is the capital of France.", "Bananas are rich in potassium."]}'
```

The response lists each document's `index` and `relevance_score`; higher is more relevant.

### Other useful endpoints

```bash
curl -H "Authorization: Bearer dummy" http://localhost:8000/v1/models   # which model this server runs
curl http://localhost:8000/health                                       # 200 when ready (no key needed)
```

---

## Running on NVIDIA (Linux, Docker, Kubernetes)

The NVIDIA side uses `configs/nvidia/`: same models, names and ports as the Mac, tuned for NVIDIA GPUs. Differences
from Mac: the server listens on all network interfaces, takes its API key from the `VLLM_API_KEY` environment
variable (never stored in the config), and uses most of the GPU's memory.

**Not run yet:** these paths have been checked statically (Docker Compose config, Kubernetes schema validation)
but not on real NVIDIA hardware. Run `./test.sh` the first time you use each model.

### Linux

**You need:** an NVIDIA GPU with drivers (`nvidia-smi` works) and internet access.

```bash
export VLLM_API_KEY=<choose-a-key>
./setup.sh                                        # pip install vllm==0.32.0 into .venv
./test-model.sh configs/nvidia/qwen3-8b.yaml
```

### Docker

**You need:** Docker and the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/). Uses the official
`vllm/vllm-openai` image, the same one Kubernetes uses, so it's a good check before deploying.

```bash
cd docker
cp .env.example .env                              # set VLLM_API_KEY (and HF_TOKEN for Llama/Gemma)
docker compose up -d qwen3-8b                     # each model is a service; nothing starts unless named
docker compose logs -f qwen3-8b                   # wait for "Application startup complete"
VLLM_API_KEY=<key> ../test.sh ../configs/nvidia/qwen3-8b.yaml
docker compose down
```

### Kubernetes (GKE)

`k8s/` is a template that deploys **Qwen3-8B on one NVIDIA L4 GPU**. **You need:** a GKE cluster with a GPU node pool
(`nvidia-l4`) and GPU quota in the region.

```bash
kubectl create secret generic vllm-secrets --from-literal=api-key=<key> --from-literal=hf-token=<token>
kubectl apply -f k8s/pvc.yaml -f k8s/configmap.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl rollout status deploy/vllm-qwen3-8b --timeout=20m      # first start downloads ~16 GB
kubectl port-forward svc/vllm-qwen3-8b 8002:8002 &
VLLM_API_KEY=<key> ./test.sh configs/nvidia/qwen3-8b.yaml
```

| File | Purpose |
|---|---|
| `deployment.yaml` | Runs the vLLM container on a GPU node, with health checks |
| `service.yaml` | Internal address other services use: `http://vllm-qwen3-8b.<namespace>.svc.cluster.local:8002/v1` |
| `configmap.yaml` | The model config (a copy of `configs/nvidia/qwen3-8b.yaml`) |
| `pvc.yaml` | Disk for the model files, so restarts don't re-download |
| `secret.example.yaml` | Template for the API key and Hugging Face token (never commit real values) |

For another model: copy the files, replace `qwen3-8b`, paste its `configs/nvidia/*.yaml` into the ConfigMap, change
the port, and pick a GPU that fits (L4 24 GB for models up to ~8B; A100/H100 for larger).

---

## Adding a model

1. Copy a config of the same type in `configs/mac/` and `configs/nvidia/`.
2. Change `model` (the Hugging Face id), `served-model-name` (the name clients send) and `port`.
3. Keep the `# type:` line right (`chat`, `reasoning`, `decision`, `embed`, `rerank`); the tests use it.
4. For tool calling, set the parser for the model family: `hermes` (Qwen), `llama3_json` (Llama), `mistral`
   (Mistral), `openai` (gpt-oss). The full list is in `vllm serve --help=all`.
5. Set `max-model-len` within the model's context window.
6. On Mac, prefer a 4-bit `mlx-community/...` copy if one exists; it's smaller and faster.
7. Run `./test-model.sh configs/mac/<new>.yaml`.
8. For Docker, add a service block to `docker/docker-compose.yml`.

---

## Disk space: status and cleanup

Models are large (0.6–14 GB each) and are stored in the shared Hugging Face cache (`~/.cache/huggingface`).

```bash
./status.sh                          # running servers, downloaded models, disk used (changes nothing)

./cleanup.sh --models                # delete all models used by configs/ (re-downloaded on next start)
./cleanup.sh --models qwen3-8b       # just one model
./cleanup.sh --env                   # delete .venv (./setup.sh recreates it)
./cleanup.sh --caches                # download caches and unfinished downloads
./cleanup.sh --docker                # vLLM Docker containers, image and model volume
./cleanup.sh --all                   # all of the above
```

`cleanup.sh` always shows what it will delete and asks first (`--yes` skips the question). It only deletes models
named in `configs/`, never other projects' models, and never the repo's own files.

---

## Troubleshooting

| Problem | What to do |
|---|---|
| `port 8000 is already in use` | Another server is running. `./status.sh` shows it; stop it, or use `--port` |
| First start takes long | It's downloading the model (sizes in [Models](#models)). Later starts take seconds |
| Answer is empty on a thinking model | `max_tokens` ran out while it was thinking; raise it |
| Tool call comes back as text | That model has no tool parser configured (see the Models table), or the parser doesn't match its family |
| `401 Unauthorized` | Missing or wrong API key (`dummy` on Mac) |
| `403` / "gated repo" on download | Accept the model's license on huggingface.co and log in: `hf auth login` |
| Mac becomes slow | Mac memory is shared with your apps. Run one or two models at a time |
| A test fails | Look at `logs/<model>.log` |
| "Found ulimit of 2048" warning | Harmless on Mac |

---

## Repo layout

```
setup.sh          install vLLM into .venv (Mac: vLLM + vllm-metal; Linux: pip install vllm)
serve.sh          start one model:                 ./serve.sh configs/<mac|nvidia>/<model>.yaml
test-model.sh     start + test + stop one model:   ./test-model.sh configs/<mac|nvidia>/<model>.yaml
test.sh           check an already-running server: ./test.sh configs/<mac|nvidia>/<model>.yaml
status.sh         what's running and disk used (read-only)
cleanup.sh        free disk space (asks first)
configs/mac/      one file per model, for Apple Silicon
configs/nvidia/   the same models, for NVIDIA GPUs (Linux, Docker, Kubernetes)
docker/           docker-compose.yml (one service per model) + .env.example
k8s/              Kubernetes template (Qwen3-8B on GKE)
PENDING.md        open items: unverified parts, known limitations, to-dos

not in git:  .venv/ (Python environment)   logs/ (server logs)   docker/.env (your keys)
```
