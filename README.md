# cosmos3-nano-vllm-eks-poc

Deploy **NVIDIA Cosmos3-Nano** (a ~16B omni-modal physical-AI reasoning model)
on **Amazon EKS** using **vLLM**, with nothing but Terraform + a handful of
Kubernetes manifests and shell scripts. Call it through an OpenAI-compatible
`/v1/chat/completions` API over `kubectl port-forward`.

```text
terraform apply
  -> EKS Cluster
  -> Managed GPU Node Group (g6e / L40S)
  -> NVIDIA Kubernetes device plugin
  -> vLLM Pod serving nvidia/Cosmos3-Nano
  -> ClusterIP Service
  -> kubectl port-forward 8000:8000
  -> POST /v1/chat/completions   (text / image / video)
```

> **This is a PoC GitHub sample, NOT a production system.** No ALB, no Ingress,
> no autoscaling, no multi-replica, no auth, no NIM. See
> [What changes for production](#what-changes-for-production).

## Why vLLM instead of NIM

The original design used the NVIDIA NIM container
`nvcr.io/nim/nvidia/cosmos3-reasoner`. But NIM images are gated behind an NGC
entitlement/subscription — pulling with a plain API key returns
`DENIED: Payment Required` (confirmed on this project: the key authenticated
fine, but its NGC org had no NIM entitlement, so *every* NIM repo — cosmos3 and
even `meta/llama-3.1-8b-instruct` — returned HTTP 402).

To keep the sample frictionless, this PoC serves the **open Hugging Face
checkpoint `nvidia/Cosmos3-Nano` with vLLM** instead. No NGC key, no NIM.

## Prerequisites

- AWS CLI, Terraform (>= 1.6), `kubectl`, `helm`, `curl`, `jq`
- AWS credentials able to create VPC / EKS / IAM / EC2
- **EC2 GPU quota + capacity for `g6e`.** This uses plain EC2 GPU quota (the
  "Running On-Demand G and VT instances" vCPU limit), *not* SageMaker quota.
  On new accounts this limit is often **0** and needs a quota-increase request
  (can take hours). Check and request before `apply`:
  ```bash
  # G/VT On-Demand vCPU limit (need >= 8 for g6e.2xlarge, plus headroom)
  aws service-quotas get-service-quota \
    --service-code ec2 --quota-code L-DB2E81BA --region "$AWS_REGION"
  ```
  Also pick a region/AZ that actually offers g6e (e.g. `us-east-1`, `us-west-2`,
  `us-east-2`) — it is not in every AZ. This sample was verified in `us-west-2`.
- Optional `HF_TOKEN` (the model is public, but a token helps with rate limits)

## Quick start

```bash
# 0. sanity check tools + credentials
./scripts/00-check-prereqs.sh

# 1. infra
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars (region, instance type, ...)
cd terraform && terraform init && terraform apply && cd ..

# 2. kubeconfig  (AWS_REGION must match terraform.tfvars; e.g. us-west-2)
export AWS_REGION=us-west-2 CLUSTER_NAME=cosmos3-vllm-poc
./scripts/01-update-kubeconfig.sh

# 3. NVIDIA device plugin (advertises nvidia.com/gpu)
./scripts/02-install-device-plugin.sh

# 4. optional Hugging Face token secret
export HF_TOKEN=hf_xxx          # optional
./scripts/03-create-hf-secret.sh

# 5. deploy vLLM + wait (model download + init can take many minutes)
./scripts/04-deploy-cosmos-vllm.sh
./scripts/05-wait-cosmos-vllm.sh
kubectl -n cosmos logs deploy/cosmos3-nano-vllm -f   # watch progress

# 6. port-forward (keep this running in one terminal)
./scripts/06-port-forward.sh

# 7. smoke test (second terminal)
./scripts/07-invoke-text.sh
./scripts/08-invoke-image.sh <image_url>
./scripts/09-invoke-video.sh <video_url>
```

`make` targets mirror these steps (`make check tf-apply kubeconfig
device-plugin hf-secret deploy wait port-forward invoke-text ...`).

## Verify GPU is allocatable

```bash
kubectl get nodes \
  -o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
# expect the g6e node to show GPU = 1
```

## The vLLM container image

The Deployment uses **`vllm/vllm-omni:cosmos3`** — NVIDIA's release-tested image
that bundles the `vllm-cosmos3` plugin. **The plain `vllm/vllm-openai` image does
not support the Cosmos3 architecture and fails at startup.** This image and its
serving command were verified end-to-end on an EC2 `g6e` (L40S): text and image
reasoning both worked. See [docs/DESIGN.md](docs/DESIGN.md) for the two flags that
matter (`--max-model-len` and `--media-io-kwargs`). To update, edit
`manifests/cosmos3-nano-vllm-deployment.yaml`.

## Cost

Not free. Cost drivers: EKS control plane, NAT gateway, the g6e GPU instance,
EBS root volumes, data transfer. **Tear down when done:**

```bash
./scripts/10-clean-k8s.sh
cd terraform && terraform destroy
```

## What changes for production

ALB/API Gateway, auth, rate limiting, ECR mirror of the vLLM image, persistent
model cache (gp3 PVC / EFS / FSx / pre-baked AMI), External Secrets, CloudWatch /
Prometheus / DCGM, HPA + Karpenter, multi-replica, canary/blue-green, SG
hardening, NetworkPolicy, cost alarms, and model-quality evaluation. See
[docs/DESIGN.md](docs/DESIGN.md).

## Docs

- [docs/DESIGN.md](docs/DESIGN.md) — architecture and design decisions (incl. the SageMaker→EKS and NIM→vLLM pivots)
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- [docs/LINKS.md](docs/LINKS.md)

## License

This sample repo is provided as-is. The model `nvidia/Cosmos3-Nano` is under
NVIDIA's OpenMDW 1.1 license — review it before use.
