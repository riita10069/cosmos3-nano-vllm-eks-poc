#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f manifests/cosmos3-nano-vllm-service.yaml --ignore-not-found
kubectl delete -f manifests/cosmos3-nano-vllm-deployment.yaml --ignore-not-found
kubectl -n cosmos delete secret hf-token-secret --ignore-not-found

# Also remove the NVIDIA device plugin Helm release and its namespace so the
# cluster is left clean (harmless before `terraform destroy`, which deletes the
# whole cluster, but matters if you keep the cluster and redeploy).
if command -v helm >/dev/null 2>&1; then
  helm uninstall nvdp -n nvidia 2>/dev/null || true
fi
kubectl delete namespace nvidia --ignore-not-found
kubectl delete namespace cosmos --ignore-not-found

echo "Kubernetes workload resources deleted."
echo "Run terraform destroy under terraform/ to delete AWS infrastructure."
