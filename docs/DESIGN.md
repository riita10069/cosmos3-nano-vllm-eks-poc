# DESIGN

## Goal

A minimal, repeatable **PoC** that stands up NVIDIA **Cosmos3-Nano** on Amazon
EKS via **vLLM**, callable through an OpenAI-compatible API over
`kubectl port-forward`. Optimized for "it starts and answers", not production.

## Architecture

```text
Developer laptop
  | terraform apply
  v
AWS account
  +-- VPC (2 public + 2 private subnets, 1 NAT gateway)
  +-- EKS cluster
        +-- system node group   (AL2023 STANDARD, m7i.large)   -> CoreDNS etc.
        +-- gpu node group       (AL2023 NVIDIA, g6e.2xlarge)
              - taint  nvidia.com/gpu=true:NoSchedule
              - labels workload=cosmos, accelerator=nvidia, nodepool=gpu-cosmos

Kubernetes
  +-- NVIDIA device plugin (Helm)   -> advertises nvidia.com/gpu
  +-- namespace/cosmos
        +-- (optional) Secret hf-token-secret
        +-- Deployment cosmos3-nano-vllm   (vllm/vllm-omni:cosmos3, 1x nvidia.com/gpu)
        +-- Service    cosmos3-nano-vllm    (ClusterIP :8000)

Local client
  +-- kubectl port-forward svc/cosmos3-nano-vllm 8000:8000
  +-- POST http://127.0.0.1:8000/v1/chat/completions
```

## Key decisions

### Terraform owns AWS infra only

Terraform creates VPC, subnets, NAT, EKS, node groups, IAM, SGs, core addons
(vpc-cni, kube-proxy, coredns), and outputs. It intentionally does **not** create
Kubernetes workloads, the device plugin, the HF token, or any Secret. That keeps
`HF_TOKEN` out of Terraform state and makes the k8s layer fast to iterate via
`scripts/` + `kubectl`/`helm`.

### emptyDir for the HF cache

The PoC mounts an `emptyDir` for `HF_HOME` instead of a PVC — no EBS CSI driver,
no IRSA, no StorageClass/PVC troubleshooting. Trade-off: a pod restart re-downloads
the ~16B model. Production should use a gp3 PVC / EFS / FSx or a pre-baked cache.

### Container image and serving command (verified on real hardware)

The Deployment uses **`vllm/vllm-omni:cosmos3`**, NVIDIA's release-tested image
that bundles the `vllm-cosmos3` plugin (vLLM 0.21.0). The plain
`vllm/vllm-openai` image does **not** recognize the Cosmos3 architecture and
fails at engine startup (`Model architectures ['Cosmos3...'] are not supported`).

This image + command were validated on an EC2 `g6e.xlarge` (L40S 48 GB): both a
text prompt and an image prompt returned correct answers via
`/v1/chat/completions`. Two non-obvious flags matter:

- **`--max-model-len 32768`** — the model's default max length (262144) requires
  ~36 GB of KV cache; an L40S only has ~21 GB free after weights, so engine init
  fails with a `ValueError`. 32768 fits comfortably and is ample for a PoC. Raise
  it on larger-memory GPUs (H100/H200).
- **`--media-io-kwargs '{"video": {"num_frames": -1}}'`** — matches NVIDIA's
  reasoner serving guidance for video inputs.

Note: the model card's `--hf-overrides '{"architectures":
["Cosmos3ReasonerForConditionalGeneration"]}'` is **not** used — this image's
vLLM only accepts the config.json default `Cosmos3ForConditionalGeneration`,
which serves chat/reasoning correctly. `VLLM_USE_DEEP_GEMM=0` is set defensively
per the Cosmos cookbook to avoid a DeepGEMM-unavailable startup failure.

### Generous probes / timeouts

First boot pulls the vLLM image (~10 GB), downloads ~28 GB of weights from Hugging
Face, and initializes the engine — this can take many minutes. The startupProbe
allows up to ~60 min (120 × 30s) before the container is considered failed; while
it runs, Kubernetes disables the readiness/liveness probes, so those only take
effect once the server is up. (`--init-timeout` is intentionally *not* passed —
it is not a recognized flag in the vLLM 0.21 build inside `vllm/vllm-omni:cosmos3`
and the container errors out if you add it.)

## History: two pivots

1. **SageMaker → EKS.** Cosmos3-Nano runs on a single L40S-class GPU (48 GB).
   SageMaker `ml.g6e` *endpoint* quota was 0 in every region checked, while the
   plain **EC2 g6e** On-Demand quota could be raised and capacity was launchable.
   So hosting moved to EKS on `g6e`. The sample was verified on `g6e` (L40S 48 GB)
   and defaults to `g6e.2xlarge` for CPU/RAM headroom during model load.
2. **NIM → vLLM.** The NGC key authenticated but its org lacked NIM entitlement, so
   every NIM pull returned `402 Payment Required` (cosmos3 and llama alike). Rather
   than enroll in a paid/trial NVIDIA AI Enterprise subscription, the PoC serves the
   open HF checkpoint with vLLM — no NGC dependency at all.

## What changes for production

ALB or API Gateway; authn/authz; request validation; rate limiting; structured
prompt templates; ECR mirror of the vLLM image; persistent model cache
(gp3/EFS/FSx/pre-baked); External Secrets / Secrets Manager; CloudWatch /
Prometheus / DCGM exporter; HPA + Karpenter; multi-replica; canary / blue-green;
security-group hardening; NetworkPolicy; cost alarms; model-quality evaluation.

**This PoC is not safety-certified and must not be used for autonomous-driving
control or planning.**
