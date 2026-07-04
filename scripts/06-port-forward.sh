#!/usr/bin/env bash
set -euo pipefail

echo "Forwarding local port 8000 to vLLM service."
echo "Open another terminal and run scripts/07-invoke-text.sh, 08-invoke-image.sh, or 09-invoke-video.sh."

kubectl -n cosmos port-forward svc/cosmos3-nano-vllm 8000:8000
