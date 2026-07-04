#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f manifests/cosmos3-nano-vllm-service.yaml --ignore-not-found
kubectl delete -f manifests/cosmos3-nano-vllm-deployment.yaml --ignore-not-found
kubectl -n cosmos delete secret hf-token-secret --ignore-not-found

echo "Kubernetes workload resources deleted."
echo "Run terraform destroy under terraform/ to delete AWS infrastructure."
