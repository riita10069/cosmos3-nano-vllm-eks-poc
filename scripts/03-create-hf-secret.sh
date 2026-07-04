#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/namespace.yaml

if [[ -z "${HF_TOKEN:-}" ]]; then
  echo "HF_TOKEN is not set."
  echo "Creating no Hugging Face token secret."
  echo "If the model is gated in your environment, set HF_TOKEN and rerun this script."
  exit 0
fi

kubectl -n cosmos delete secret hf-token-secret --ignore-not-found
kubectl -n cosmos create secret generic hf-token-secret \
  --from-literal=HF_TOKEN="$HF_TOKEN"

echo "Created hf-token-secret in namespace/cosmos."
