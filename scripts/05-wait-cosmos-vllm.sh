#!/usr/bin/env bash
set -euo pipefail

echo "Cosmos3-Nano model download and vLLM initialization can take a long time."
echo "Streaming rollout status..."

kubectl -n cosmos rollout status deploy/cosmos3-nano-vllm --timeout=7200s

kubectl -n cosmos get pods -o wide
