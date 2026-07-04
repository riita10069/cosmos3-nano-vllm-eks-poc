#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="${1:-https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Fronalpstock_big.jpg/1280px-Fronalpstock_big.jpg}"

curl -sS http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @- <<EOF | jq .
{
  "model": "nvidia/Cosmos3-Nano",
  "messages": [
    {
      "role": "system",
      "content": "You are a physical-world visual reasoning assistant."
    },
    {
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {
            "url": "${IMAGE_URL}"
          }
        },
        {
          "type": "text",
          "text": "Describe the image. Then list visible objects and uncertainty."
        }
      ]
    }
  ],
  "max_tokens": 512,
  "stream": false
}
EOF
