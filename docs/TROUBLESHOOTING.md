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

**Device plugin shows `DESIRED 0` / GPU stays 0 on a tainted node.** The chart's
node-feature-discovery (NFD) worker only tolerates `nvidia.com/gpu=present`, but
this sample taints the GPU node `nvidia.com/gpu=true`. Without a matching
toleration the NFD worker never lands on the GPU node, so the node is never
labeled and the plugin never schedules. `scripts/02-install-device-plugin.sh`
fixes this by overriding the NFD worker toleration to `operator: Exists`. If you
install the chart manually, pass the same override.

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

## `Model architectures ['Cosmos3...'] are not supported`

You are using the wrong image. The Cosmos3 architecture is only available in
**`vllm/vllm-omni:cosmos3`** (bundles the `vllm-cosmos3` plugin), not in
`vllm/vllm-openai`. The manifest already uses the omni image; if you changed it,
change it back.

## Engine init `ValueError: ... KV cache is needed, which is larger than available`

The model's default max length (262144) needs ~36 GB of KV cache; an L40S has
only ~21 GB free after weights. The manifest sets `--max-model-len 32768` to fit.
If you raised it, lower it again, or move to a larger-memory GPU (H100/H200).

## Image URL returns 403 / Forbidden

Some hosts (e.g. Wikimedia) reject fetches with no browser User-Agent, which is
how vLLM fetches media. Use a permissive host such as
`https://raw.githubusercontent.com/...`. The sample's default image URL already
points at one.
