#!/usr/bin/env bash
# exo-start-4gpu.sh — sobe 4 nós exo no AC922, um por V100.
#   nó 0: GPU 0, API 52415, zenoh 52414, discovery 52413  (é o nó que os outros e o laptop discam)
#   nó i: GPU i, sem API,   zenoh 52414+10i, discovery 52413+10i, bootstrap -> tcp/127.0.0.1:52414
# Uso: exo-start-4gpu.sh          (para tudo e sobe os 4)
#      exo-start-4gpu.sh --stop   (só para)
set -euo pipefail

EXO_ENV=exo-ppc64le
EXO_MODELS_RO="$HOME/exo-models-ro"
SHARED_MODELS="$HOME/.local/share/exo/models"   # caches de file list ficam aqui
VRAM_MB=15000                                   # 16 GB da V100 menos folga
LOGDIR="$HOME/.cache/exo-4gpu"
NGPU=4

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$EXO_ENV"

if pgrep -f 'bin/exo( |$)' >/dev/null; then
  echo "parando exo(s) em execução..."
  pkill -f 'bin/exo( |$)' || true
  sleep 4
fi
[[ "${1:-}" == "--stop" ]] && { echo "exo parado."; exit 0; }

mkdir -p "$LOGDIR" "$EXO_MODELS_RO"
export EXO_OFFLINE=true
export EXO_MODELS_READ_ONLY_DIRS="$EXO_MODELS_RO"
export EXO_MEMORY_FROM_GPU=1   # memória do nó = VRAM da sua V100 (NVML)

for i in $(seq 0 $((NGPU-1))); do
  home=".exo-gpu$i"                                   # EXO_HOME é relativo ao $HOME
  mkdir -p "$HOME/$home"
  # cada nó tem seu node id e pidfile em ~/.exo-gpuN, mas compartilha os caches de modelos
  [[ -e "$HOME/$home/models" ]] || ln -s "$SHARED_MODELS" "$HOME/$home/models"

  zp=$((52414 + 10*i)); dp=$((52413 + 10*i))
  args=(--zenoh-port "$zp" --discovery-port "$dp")
  if [[ $i -eq 0 ]]; then
    args+=(--api-port 52415 --force-master)
  else
    args+=(--no-api --bootstrap-peers "tcp/127.0.0.1:52414")
  fi

  EXO_HOME="$home" CUDA_VISIBLE_DEVICES=$i nohup exo -v "${args[@]}" >"$LOGDIR/gpu$i.log" 2>&1 &
  echo "nó $i: GPU $i, zenoh $zp (pid $!) -> $LOGDIR/gpu$i.log"
  [[ $i -eq 0 ]] && sleep 8      # nó 0 de pé antes dos outros discarem
done

for _ in $(seq 1 40); do
  n=$(curl -sf localhost:52415/state 2>/dev/null | python -c "import json,sys; print(len(json.load(sys.stdin)['topology']['nodes']))" 2>/dev/null || echo 0)
  [[ "$n" -ge "$NGPU" ]] && { echo "cluster pronto: $n nós (API http://localhost:52415)"; exit 0; }
  sleep 2
done
echo "só $n nós visíveis após 80 s — veja os logs em $LOGDIR"; exit 1
