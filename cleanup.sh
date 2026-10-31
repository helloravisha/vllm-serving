#!/usr/bin/env bash
# Free disk space. Shows what will be deleted and asks first. Never touches the repo files.
#   ./cleanup.sh --models            model weights used by configs/ (re-downloaded on next ./serve.sh)
#   ./cleanup.sh --models qwen3-8b   only the models of matching config names
#   ./cleanup.sh --env               .venv (re-create with ./setup.sh)
#   ./cleanup.sh --caches            ~/.cache/vllm, ~/.cache/uv and incomplete HF downloads
#   ./cleanup.sh --docker            vLLM containers, image and the hf-cache volume
#   ./cleanup.sh --all               all of the above
#   add --yes to skip the confirmation prompt
set -uo pipefail
cd "$(dirname "$0")"

if [[ -x .venv/bin/hf ]]; then HF=(.venv/bin/hf); else HF=(uvx --from huggingface_hub hf); fi
models=0 env=0 caches=0 dock=0 yes=0 filters=()
for a in "$@"; do
  case "$a" in
    --models) models=1 ;;
    --env)    env=1 ;;
    --caches) caches=1 ;;
    --docker) dock=1 ;;
    --all)    models=1 env=1 caches=1 dock=1 ;;
    --yes|-y) yes=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option $a" >&2; exit 1 ;;
    *)  filters+=("$a") ;;
  esac
done
if [[ $((models + env + caches + dock)) -eq 0 ]]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  echo; echo "Nothing selected. Run ./status.sh to see what is using disk."
  exit 0
fi

size_kb() { [[ -e "$1" ]] && du -sk "$1" 2>/dev/null | cut -f1 || echo 0; }
human()   { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1f GB", k/1048576; else if (k >= 1024) printf "%.0f MB", k/1024; else printf "%d KB", k }'; }

paths=() repos=() total=0
add() { [[ -e "$1" ]] || return 0; local kb; kb=$(size_kb "$1"); paths+=("$1"); total=$((total + kb)); printf "  %-60s %s\n" "${1/#$HOME/~}" "$(human "$kb")"; }

echo "Will delete:"
if [[ $models -eq 1 ]]; then
  cfgs=(configs/*/*.yaml)
  if [[ ${#filters[@]} -gt 0 ]]; then
    cfgs=(); for f in "${filters[@]}"; do cfgs+=(configs/*/*"$f"*.yaml); done
  fi
  # Delete via the hf CLI: the HF cache shares large files between repos, so removing folders by hand leaks them.
  cached=$("${HF[@]}" cache ls --json 2>/dev/null)
  for ckpt in $(awk -F': *' '$1=="model"{print $2}' "${cfgs[@]}" 2>/dev/null | sort -u); do
    size=$(python3 -c 'import json,sys; print(next((r["size"] for r in json.loads(sys.argv[1]) if r["repo_id"] == sys.argv[2]), ""))' "$cached" "$ckpt")
    [[ -n "$size" ]] || continue
    repos+=("model/$ckpt")
    printf "  %-60s %sB\n" "HF model $ckpt" "$size"
  done
fi
[[ $env -eq 1 ]] && add .venv
if [[ $caches -eq 1 ]]; then
  add "$HOME/.cache/vllm"; add "$HOME/.cache/uv"
  incomplete=$("${HF[@]}" cache ls 2>&1 | sed -n 's/.*Found \([0-9]* incomplete download(s) totalling [0-9.]*[KMGT]*\).*/\1/p')
  [[ -n "$incomplete" ]] && printf "  %-60s\n" "HF cache: $incomplete"
fi

docker_ok=0
if [[ $dock -eq 1 ]]; then
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    docker_ok=1
    docker ps -a --filter ancestor=vllm/vllm-openai --format '  container {{.Names}}' 2>/dev/null
    docker images vllm/vllm-openai --format '  image     {{.Repository}}:{{.Tag}} ({{.Size}})' 2>/dev/null
    docker volume ls -q --filter name=hf-cache 2>/dev/null | sed 's/^/  volume    /'
  else
    echo "  (docker not available, skipping)"
  fi
fi

if [[ ${#paths[@]} -eq 0 && ${#repos[@]} -eq 0 && -z "${incomplete:-}" && $docker_ok -eq 0 ]]; then
  echo "  nothing found"; exit 0
fi
[[ ${#paths[@]} -gt 0 ]] && echo "Total of the folders above: $(human "$total")"

if [[ $yes -ne 1 ]]; then
  read -r -p "Delete these? [y/N] " ans
  [[ "$ans" == [yY]* ]] || { echo "Cancelled."; exit 0; }
fi

if [[ $models -eq 1 || $env -eq 1 ]] && pgrep -f "vllm serve" >/dev/null; then
  echo "Stopping running vLLM servers..."
  pkill -f "vllm serve"; sleep 3
fi
if [[ ${#repos[@]} -gt 0 ]]; then
  "${HF[@]}" cache rm "${repos[@]}" -y >/dev/null && printf "deleted %s\n" "${repos[@]}"
fi
if [[ -n "${incomplete:-}" ]]; then
  "${HF[@]}" cache prune -y >/dev/null && echo "removed incomplete HF downloads"
fi
for p in "${paths[@]}"; do rm -rf "$p" && echo "deleted ${p/#$HOME/~}"; done
if [[ $docker_ok -eq 1 ]]; then
  docker ps -aq --filter ancestor=vllm/vllm-openai | xargs -r docker rm -f >/dev/null
  docker images -q vllm/vllm-openai | xargs -r docker rmi -f >/dev/null
  docker volume ls -q --filter name=hf-cache | xargs -r docker volume rm >/dev/null
  echo "removed vLLM docker containers, image and model volume"
fi
echo "Done."
