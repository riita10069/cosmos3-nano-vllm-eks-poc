#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-cosmos}"
DEPLOYMENT="${DEPLOYMENT:-cosmos3-nano-vllm}"
EXPECTED_IMAGE_DIGEST="sha256:970dee6658ea223f615b2438ce41e47f1d5322225482546e6e6bc5d8134f757c"
EXPECTED_MODEL_REVISION="411f42a8fdfb8c5b2583cb8786e0938f49796eaa"

pod="$(
  kubectl -n "$NAMESPACE" get pods -l "app=$DEPLOYMENT" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "$pod" ]]; then
  echo "No running pod found for deployment/$DEPLOYMENT in namespace/$NAMESPACE." >&2
  exit 1
fi

deployment_json="$(kubectl -n "$NAMESPACE" get deployment "$DEPLOYMENT" -o json)"
image="$(
  jq -r '.spec.template.spec.containers[] | select(.name == "vllm") | .image' \
    <<<"$deployment_json"
)"
command="$(
  jq -r '[.spec.template.spec.containers[] | select(.name == "vllm") | .command[]] | join(" ")' \
    <<<"$deployment_json"
)"
deep_gemm="$(
  jq -r '
    .spec.template.spec.containers[]
    | select(.name == "vllm")
    | .env[]
    | select(.name == "VLLM_USE_DEEP_GEMM")
    | .value
  ' <<<"$deployment_json"
)"
image_id="$(
  kubectl -n "$NAMESPACE" get pod "$pod" -o json |
    jq -r '.status.containerStatuses[] | select(.name == "vllm") | .imageID'
)"

[[ "$image" == *"@$EXPECTED_IMAGE_DIGEST" ]] || {
  echo "Deployment image is not pinned to the expected digest: $image" >&2
  exit 1
}
[[ "$image_id" == *"$EXPECTED_IMAGE_DIGEST" ]] || {
  echo "Running pod image digest does not match: $image_id" >&2
  exit 1
}
[[ "$command" == *"--tensor-parallel-size 1"* ]] || {
  echo "Expected tensor parallel size 1, got: $command" >&2
  exit 1
}
[[ "$command" == *"--max-model-len 32768"* ]] || {
  echo "Expected max model length 32768, got: $command" >&2
  exit 1
}
[[ "$command" == *"--revision $EXPECTED_MODEL_REVISION"* ]] || {
  echo "Expected model revision is missing: $command" >&2
  exit 1
}
[[ "$command" == *'--media-io-kwargs {"video": {"num_frames": -1}}'* ]] || {
  echo "Expected video media I/O settings are missing: $command" >&2
  exit 1
}
[[ "$command" != *"--async-scheduling"* ]] || {
  echo "Unexpected async scheduling flag found: $command" >&2
  exit 1
}
[[ "$deep_gemm" == "0" ]] || {
  echo "Expected VLLM_USE_DEEP_GEMM=0, got: $deep_gemm" >&2
  exit 1
}

model_snapshot="$(
  kubectl -n "$NAMESPACE" exec "$pod" -- sh -ceu \
    'find /cache/huggingface/hub/models--nvidia--Cosmos3-Nano/snapshots -mindepth 1 -maxdepth 1 -type d -exec basename {} \;'
)"
grep -Fxq "$EXPECTED_MODEL_REVISION" <<<"$model_snapshot" || {
  echo "Expected model revision is not present in the Hugging Face cache: $model_snapshot" >&2
  exit 1
}

kubectl get nodes -l workload=cosmos -o json |
  jq -e '
    .items | length == 1 and .[0].status.allocatable["nvidia.com/gpu"] == "1"
  ' >/dev/null || {
  echo "Expected one Cosmos node with one allocatable GPU." >&2
  exit 1
}

models_json="$(
  kubectl -n "$NAMESPACE" exec "$pod" -- python3 -c '
from urllib.request import urlopen
print(urlopen("http://127.0.0.1:8000/v1/models", timeout=10).read().decode())
'
)"
model_id="$(jq -r '.data[0].id' <<<"$models_json")"
[[ "$model_id" == "nvidia/Cosmos3-Nano" ]] || {
  echo "Expected served model nvidia/Cosmos3-Nano, got: $model_id" >&2
  exit 1
}

jq -n \
  --arg pod "$pod" \
  --arg image "$image" \
  --arg image_id "$image_id" \
  --arg model_revision "$EXPECTED_MODEL_REVISION" \
  --arg model_id "$model_id" \
  --arg scheduler "vllm default continuous batching" \
  --argjson client_concurrency 4 \
  '{
    pod: $pod,
    configured_image: $image,
    running_image_id: $image_id,
    model_revision: $model_revision,
    served_model_id: $model_id,
    scheduler: $scheduler,
    reference_client_concurrency: $client_concurrency,
    status: "verified"
  }'
