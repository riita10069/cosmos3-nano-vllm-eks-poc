#!/usr/bin/env bash
set -euo pipefail

# Default image is hosted on raw.githubusercontent.com because it serves
# without a User-Agent requirement. (Wikimedia returns HTTP 403 to the vLLM
# fetcher, which has no browser User-Agent.) Pass any public image URL as $1.
IMAGE_URL="${1:-https://raw.githubusercontent.com/pytorch/hub/master/images/dog.jpg}"

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
