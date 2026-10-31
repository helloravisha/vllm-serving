# Pending

Open items for this repo, as of 2026-10-31. Gateway-side work is tracked in the LLM Gateway repo's
`PENDING_FIXES.md` (items 16 and 17).

## Not verified yet

- **NVIDIA side never run.** `configs/nvidia/`, the Linux path of `setup.sh`, `docker/` and `k8s/` have only been
  checked statically (Docker Compose config, Kubernetes 1.33 schema validation). First real run needs a Linux
  NVIDIA machine or a GKE GPU node pool; run `./test.sh` on every config used.
- **Gated weights on NVIDIA.** `meta-llama/Llama-3.1-8B-Instruct` and `google/gemma-3-12b-it` returned 403 for
  the current Hugging Face account: accept the licenses on the model pages, then use a token with access
  (`HF_TOKEN` in `docker/.env` or the `vllm-secrets` Kubernetes secret). The Mac configs use ungated mirrors.
- **`k8s/` is a single-model template** (Qwen3-8B on an L4). Each further model needs its own copy (or a Helm
  chart / kustomize overlay) and a GPU type that fits it.

## Known limitations

- **`phi4-mini` is chat-only.** Tool calling needs `examples/tool_chat_template_phi4_mini.jinja` from the vLLM
  source repo (not in the package). Enabling it means adding a `templates/` folder and mounting it in Docker/k8s.
- **`gemma3-12b` has no tool calling configured.**
- **`qwen3-reranker-0.6b` scores are compressed.** Ranking order is right, but an unrelated document still
  scored 0.79. Qwen3-Reranker expects its instruction prompt format; try that before relying on absolute
  scores or thresholds.

## To do

- **Push to a shared Git host** (e.g. GitHub) for the team; the repo exists only on this Mac. Needs a repo name
  and private/public decision.
- **Add a JSON-mode check to `test.sh`** (`response_format: json_object` / JSON schema), matching how the
  gateway's planner calls local models today, alongside the native tool-call check.
