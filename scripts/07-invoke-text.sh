#!/usr/bin/env bash
set -euo pipefail

# Preflight: the endpoint is reached via `scripts/06-port-forward.sh`.
if ! curl -sf -o /dev/null http://127.0.0.1:8000/v1/models; then
  echo "Cannot reach http://127.0.0.1:8000 — is scripts/06-port-forward.sh running?" >&2
  exit 1
fi

curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @- <<'EOF' | jq .
{
  "model": "nvidia/Cosmos3-Nano",
  "messages": [
    {
      "role": "system",
      "content": "You are a physical-world reasoning assistant."
    },
    {
      "role": "user",
      "content": "Explain what Cosmos3-Nano can do in one paragraph."
    }
  ],
  "max_tokens": 256,
  "stream": false
}
EOF
