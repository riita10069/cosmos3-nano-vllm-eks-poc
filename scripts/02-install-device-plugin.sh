#!/usr/bin/env bash
set -euo pipefail

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
helm repo update

helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia \
  --create-namespace \
  --set gfd.enabled=true

echo "Waiting for NVIDIA device plugin DaemonSet..."
kubectl rollout status ds/nvdp-nvidia-device-plugin -n nvidia --timeout=180s

echo "Allocatable GPUs:"
kubectl get nodes \
  -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
