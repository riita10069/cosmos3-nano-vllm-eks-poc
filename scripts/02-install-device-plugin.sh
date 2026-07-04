#!/usr/bin/env bash
set -euo pipefail

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
helm repo update

# The GPU node group is tainted nvidia.com/gpu=true:NoSchedule (see terraform).
# The chart's node-feature-discovery (NFD) worker hardcodes a toleration for
# value=present, so with our value=true it never lands on the GPU node, the node
# never gets the nvidia.com/gpu.present label, and the device plugin never
# schedules -> nvidia.com/gpu stays 0. Override the NFD worker to tolerate ANY
# taint so it labels the GPU node. (Verified fix on a real g6e cluster.)
cat > /tmp/nvdp-values.yaml <<'EOF'
gfd:
  enabled: true
nfd:
  worker:
    tolerations:
      - operator: "Exists"
EOF

helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia \
  --create-namespace \
  -f /tmp/nvdp-values.yaml

echo "Waiting for NVIDIA device plugin DaemonSet..."
# The plugin DaemonSet only creates pods once a node is labeled as having a GPU,
# so give NFD a moment before waiting on the rollout.
sleep 20
kubectl rollout status ds/nvdp-nvidia-device-plugin -n nvidia --timeout=180s

echo "Allocatable GPUs:"
kubectl get nodes \
  -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
