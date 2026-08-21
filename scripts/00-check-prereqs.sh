#!/usr/bin/env bash
set -euo pipefail

required=(
  aws
  terraform
  kubectl
  helm
  curl
  jq
  python3
)

for bin in "${required[@]}"; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Missing required command: $bin" >&2
    exit 1
  fi
done

aws sts get-caller-identity >/dev/null

echo "All prerequisites look good."
