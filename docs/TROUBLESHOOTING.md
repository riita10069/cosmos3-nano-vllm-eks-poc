# TROUBLESHOOTING

## Pod is Pending

```bash
kubectl -n cosmos describe pod -l app=cosmos3-nano-vllm
kubectl get nodes --show-labels
kubectl get nodes -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
```

Common causes: GPU node group not ready; GPU quota missing; `nodeSelector`
mismatch; taint/toleration mismatch; NVIDIA device plugin not installed.

## `nvidia.com/gpu` is missing / 0

```bash
kubectl get ds -n nvidia
kubectl logs -n nvidia ds/nvdp-nvidia-device-plugin
```

Confirm the GPU node group uses `AL2023_x86_64_NVIDIA`. That AMI includes the
driver + container toolkit but **not** the device plugin — install it separately
(`scripts/02-install-device-plugin.sh`).

## Model download is slow

Expected. `nvidia/Cosmos3-Nano` is ~16B params / BF16. Watch progress:

```bash
kubectl -n cosmos logs deploy/cosmos3-nano-vllm -f
```

## Pod OOMs

Use `g6e.2xlarge` instead of `g6e.xlarge`; increase memory request/limit; reduce
video input size; test text/image before video; or use a larger GPU instance.

## vLLM startup fails with DeepGEMM

The sample already sets `VLLM_USE_DEEP_GEMM=0`. NVIDIA's Cosmos cookbook notes
DeepGEMM may need disabling when the vLLM build reports it unavailable.

## Video URL fails

Check the pod can reach the URL (needs NAT egress, which this Terraform creates):

```bash
kubectl -n cosmos exec deploy/cosmos3-nano-vllm -- bash -lc 'curl -I https://example.com'
```

## API call fails

```bash
kubectl -n cosmos port-forward svc/cosmos3-nano-vllm 8000:8000
curl -v http://127.0.0.1:8000/v1/models
```

If `/v1/models` returns the model id, the server is up. If the port-forward drops,
the pod may still be initializing (not yet Ready) — re-check rollout status.

## Cosmos3-Nano not yet supported by the pinned vLLM tag

If `vllm serve` errors that the architecture/model is unknown, bump the image tag
in `manifests/cosmos3-nano-vllm-deployment.yaml` to a newer
`vllm/vllm-openai:vX.Y.Z-...` that lists Cosmos3 support, then
`kubectl -n cosmos rollout restart deploy/cosmos3-nano-vllm`.
