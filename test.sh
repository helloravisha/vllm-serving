#!/usr/bin/env bash
# Smoke-test a running vLLM server. Checks depend on the config's "# type:" line:
#   chat      -> models, chat, tool call (if tool calling is enabled)
#   reasoning -> models, chat with a separate reasoning field
#   decision  -> models, structured output restricted to a fixed set of choices
#   embed     -> models, /v1/embeddings
#   rerank    -> models, /rerank
#
#   ./test.sh configs/mac/qwen2.5-1.5b.yaml
#   URL=http://vllm-qwen3-8b:8002 VLLM_API_KEY=... ./test.sh configs/nvidia/qwen3-8b.yaml   # remote server
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:?usage: ./test.sh <config.yaml>}"
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }

exec python3 - "$CONFIG" <<'PY'
import json, os, re, sys, urllib.request, urllib.error

cfg_path = sys.argv[1]
text = open(cfg_path).read()
def field(key):
    m = re.search(rf"^{re.escape(key)}:\s*([^#\n]*)", text, re.M)
    return m.group(1).strip() if m else None
typ = (re.search(r"^#\s*type:\s*(\w+)", text, re.M) or [None, "chat"])[1]
model = field("served-model-name") or field("model")
url = os.environ.get("URL") or f"http://localhost:{field('port') or 8000}"
key = os.environ.get("VLLM_API_KEY") or field("api-key")

def call(path, body=None):
    req = urllib.request.Request(url.rstrip("/") + path, json.dumps(body).encode() if body else None,
                                 {"Content-Type": "application/json", **({"Authorization": f"Bearer {key}"} if key else {})})
    try:
        return json.load(urllib.request.urlopen(req, timeout=300))
    except urllib.error.HTTPError as e:
        fail(f"{path} -> HTTP {e.code}: {e.read().decode()[:300]}")
    except OSError as e:
        fail(f"{path} -> {e} (is the server running? ./serve.sh {cfg_path})")

def fail(msg):
    print(f"FAIL: {msg}"); sys.exit(1)
def ok(msg):
    print(f"ok:   {msg}")

print(f"== {cfg_path}  [{typ}]  {model} @ {url}")
ids = [m["id"] for m in call("/v1/models")["data"]]
if model not in ids: fail(f"server serves {ids}, not {model}")
ok("model listed")

thinking = "reasoning-parser:" in text   # thinking models need room to reason before answering
def chat(messages, **extra):
    body = {"model": model, "messages": messages, "max_tokens": 4096 if thinking else 512}
    return call("/v1/chat/completions", {**body, **extra})["choices"][0]

if typ in ("chat", "reasoning"):
    c = chat([{"role": "user", "content": "What is 17 + 25? Answer with just the number."}])
    msg = c["message"]
    if not (msg.get("content") or "").strip(): fail(f"empty answer: {c}")
    ok(f"chat -> {msg['content'].strip()[:80]!r}")
    if msg.get("reasoning"):
        ok(f"reasoning field present ({len(msg['reasoning'])} chars)")
    elif typ == "reasoning":
        fail("no separate reasoning field")
    if "enable-auto-tool-choice: true" in text:
        tools = [{"type": "function", "function": {"name": "get_weather", "description": "Get current weather for a city",
                  "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}]
        c = chat([{"role": "user", "content": "What is the weather in Paris right now?"}], tools=tools, tool_choice="auto")
        calls = c["message"].get("tool_calls") or []
        if not calls or calls[0]["function"]["name"] != "get_weather": fail(f"no get_weather tool call: {c['message']}")
        ok(f"tool call -> get_weather({calls[0]['function']['arguments']})")

elif typ == "decision":
    choices = ["code", "chat", "research"]
    c = chat([{"role": "user", "content": "Route this request: 'Write a Python function that reverses a list.' "
                                          "Answer with one of: code, chat, research."}],
             structured_outputs={"choice": choices}, chat_template_kwargs={"enable_thinking": False}, max_tokens=10)
    ans = (c["message"].get("content") or "").strip()
    if ans not in choices: fail(f"answer {ans!r} not in {choices}")
    ok(f"structured choice -> {ans!r}")

elif typ == "embed":
    r = call("/v1/embeddings", {"model": model, "input": ["How do I reset my password?", "I forgot my login", "Best pizza in Chicago"]})
    v = [d["embedding"] for d in r["data"]]
    def cos(a, b):
        return sum(x * y for x, y in zip(a, b)) / ((sum(x * x for x in a) ** .5) * (sum(y * y for y in b) ** .5))
    ok(f"embeddings -> {len(v)} vectors of {len(v[0])} dims")
    near, far = cos(v[0], v[1]), cos(v[0], v[2])
    if near <= far: fail(f"similar texts not closer: {near:.3f} vs {far:.3f}")
    ok(f"similarity: related {near:.3f} > unrelated {far:.3f}")

elif typ == "rerank":
    docs = ["Paris is the capital of France.", "Bananas are rich in potassium.", "France's capital city is Paris."]
    r = call("/rerank", {"model": model, "query": "What is the capital of France?", "documents": docs})
    ranked = sorted(r["results"], key=lambda x: -x["relevance_score"])
    if docs[ranked[-1]["index"]] != docs[1]: fail(f"unrelated document not ranked last: {ranked}")
    ok("rerank -> " + ", ".join(f"#{x['index']}={x['relevance_score']:.3f}" for x in ranked))

else:
    fail(f"unknown type {typ!r}")
print("All checks passed.")
PY
