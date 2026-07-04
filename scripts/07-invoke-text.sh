#!/usr/bin/env bash
set -euo pipefail

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
