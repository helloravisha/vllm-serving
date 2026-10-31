#!/usr/bin/env bash
# Read-only overview: running servers, downloaded models, disk used. Deletes nothing.
set -uo pipefail
cd "$(dirname "$0")"

if [[ -x .venv/bin/hf ]]; then HF=(.venv/bin/hf); else HF=(uvx --from huggingface_hub hf); fi
size_kb() { [[ -e "$1" ]] && du -sk "$1" 2>/dev/null | cut -f1 || echo 0; }
human()   { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else if (k >= 1024) printf "%.0f MB", k/1024; else printf "%d KB", k }'; }
total=0

echo "Servers"
running=0
while read -r pid cmd; do
  cfg=$(sed -n 's/.*--config \([^ ]*\).*/\1/p' <<<"$cmd")
  [[ -n "$cfg" && -f "$cfg" ]] || continue
  port=$(awk -F': *' '$1=="port"{print $2+0}' "$cfg")
  model=$(awk -F': *' '$1=="served-model-name"{sub(/ *#.*/,"",$2); print $2}' "$cfg")
  health=$(curl -s -m 2 -o /dev/null -w "%{http_code}" "http://localhost:$port/health")
  state=$([[ $health == 200 ]] && echo ready || echo starting)
  printf "  :%-5s %-45s %-8s pid %s  (%s)\n" "$port" "$model" "$state" "$pid" "$cfg"
  running=$((running + 1))
done < <(pgrep -fl "vllm serve" 2>/dev/null)
[[ $running -eq 0 ]] && echo "  none running"

echo
echo "Models used by configs/ (downloaded)"
# The HF cache shares large files between repos, so sizes come from the hf CLI, not du.
models_out=$("${HF[@]}" cache ls --json 2>/dev/null | python3 -c '
import json, sys
wanted = set(sys.argv[1:])
unit = {"K": 1, "M": 1024, "G": 1024 ** 2, "T": 1024 ** 3}
total = 0
for r in json.load(sys.stdin):
    if r["repo_id"] in wanted:
        size = r["size"]
        total += float(size[:-1]) * unit[size[-1]] if size[-1] in unit else float(size) / 1024
        print("  %-50s %sB" % (r["repo_id"], size))
print("TOTAL_KB=%d" % total)
' $(awk -F': *' '$1=="model"{print $2}' configs/*/*.yaml | sort -u))
if grep -q "^  " <<<"$models_out"; then grep "^  " <<<"$models_out"; else echo "  none downloaded"; fi
total=$(( total + $(sed -n 's/^TOTAL_KB=//p' <<<"$models_out" | grep . || echo 0) ))

echo
echo "Environment and caches"
for p in .venv "$HOME/.cache/vllm" "$HOME/.cache/uv"; do
  kb=$(size_kb "$p"); [[ $kb -gt 0 ]] || continue
  total=$((total + kb))
  printf "  %-50s %s\n" "${p/#$HOME/~}" "$(human "$kb")"
done
incomplete=$("${HF[@]}" cache ls 2>&1 | sed -n 's/.*Found \([0-9]* incomplete download(s) totalling [0-9.]*[KMGT]*\).*/\1/p')
[[ -n "$incomplete" ]] && echo "  HF cache: $incomplete  (./cleanup.sh --caches removes them)"

if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  img=$(docker images vllm/vllm-openai --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null)
  vol=$(docker volume ls -q --filter name=hf-cache 2>/dev/null)
  if [[ -n "$img$vol" ]]; then
    echo
    echo "Docker"
    [[ -n "$img" ]] && echo "  image  $img"
    [[ -n "$vol" ]] && echo "  volume $vol (model cache)"
  fi
fi

echo
echo "Total disk used (excluding Docker and incomplete downloads): $(human "$total")"
