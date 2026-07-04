#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <video_url>" >&2
  echo "Example: $0 https://example.com/clip.mp4" >&2
  exit 1
fi

VIDEO_URL="$1"

curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @- <<EOF | jq .
{
  "model": "nvidia/Cosmos3-Nano",
  "messages": [
    {
      "role": "system",
      "content": "You are an autonomous driving scene reasoning assistant."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "video_url",
          "video_url": {
            "url": "${VIDEO_URL}"
          }
        },
        {
          "type": "text",
          "text": "Analyze this driving scene from the ego vehicle perspective. Return scene_summary, relevant_agents, risk_factors, causal_reasoning, recommended_ego_behavior, and uncertainty."
        }
      ]
    }
  ],
  "max_tokens": 1024,
  "stream": false
}
EOF
