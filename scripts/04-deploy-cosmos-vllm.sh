#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/cosmos3-nano-vllm-deployment.yaml
kubectl apply -f manifests/cosmos3-nano-vllm-service.yaml

kubectl -n cosmos get deploy,po,svc
