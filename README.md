# cosmos3-nano-vllm-eks-poc

Deploy NVIDIA Cosmos3-Nano on Amazon EKS with vLLM and call the
OpenAI-compatible `/v1/chat/completions` API through `kubectl port-forward`.
This repository fixes the server artifact, model revision, EKS dependencies, and
request-concurrency profile needed to reproduce the inference environment.

```text
terraform apply
  -> EKS 1.34 cluster
  -> g6e.2xlarge L40S GPU node
  -> NVIDIA device plugin
  -> vLLM serving nvidia/Cosmos3-Nano
  -> ClusterIP service
  -> kubectl port-forward 8000:8000
  -> POST /v1/chat/completions
```

This is a single-GPU PoC, not a production service. It has no ingress,
authentication, autoscaling, persistent model cache, or multi-replica setup.

## Reproducibility contract

| Layer | Fixed value |
| --- | --- |
| Container | `vllm/vllm-omni@sha256:970dee6658ea223f615b2438ce41e47f1d5322225482546e6e6bc5d8134f757c` |
| Model | `nvidia/Cosmos3-Nano` at Hugging Face revision `411f42a8fdfb8c5b2583cb8786e0938f49796eaa` |
| vLLM runtime | Tensor parallel size 1, max model length 32768, `VLLM_USE_DEEP_GEMM=0` |
| Scheduler | vLLM default continuous batching. No unvalidated scheduler or prefill override is passed. |
| Reference client profile | Four in-flight requests, `concurrency=4` |
| AWS region and hardware | `us-west-2`, `g6e.2xlarge`, one L40S GPU |
| EKS dependencies | EKS 1.34, fixed AMI and core add-on versions in `terraform/terraform.tfvars.example` |
| Terraform provider | `hashicorp/aws` 5.100.0 and the committed `.terraform.lock.hcl` |
| GPU device plugin | `nvidia-device-plugin` Helm chart 0.20.0 |

The Docker Hub `cosmos3` tag is mutable. The Deployment uses the Linux AMD64
digest resolved on 2026-08-22 instead. The Hugging Face branch is likewise
mutable, so the manifest passes the model commit through `--revision`.

## Why the default continuous-batching profile

vLLM continuously schedules compatible active requests into GPU steps. The
server therefore needs multiple requests in flight to use the feature. This
repository keeps the server scheduler at the fixed-image defaults and controls
that load at the client with `--concurrency`.

The ROAD scene-labeling measurements used four simultaneous clips as the
latency-oriented profile. It produced 1.38 seconds mean wall time per clip,
5.75 seconds P95 latency, and USD 0.862 GPU cost per 1,000 clips. Increasing
to eight requests improved mean wall time to 1.22 seconds and reduced GPU cost
to USD 0.759 per 1,000 clips, but P95 latency rose to 13.78 seconds. Use c4 as
the default. Use c8 only when throughput matters more than tail latency.

Those measurements establish the request profile, not a substitute for a
fresh GPU validation after changing the locked image, model, hardware, or
input payload. `make verify-runtime` confirms the deployed artifacts before a
benchmark run.

## Prerequisites

- AWS CLI, Terraform 1.6 or later, `kubectl`, `helm`, `curl`, `jq`, and `python3`
- AWS credentials able to create VPC, EKS, IAM, and EC2 resources
- EC2 quota and capacity for `g6e.2xlarge` in `us-west-2a` or `us-west-2b`
- Optional `HF_TOKEN`. The model is public; a token helps with rate limits.

The required EC2 quota is the G and VT On-Demand vCPU quota, not a SageMaker
quota. Check it before provisioning:

```bash
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-DB2E81BA --region us-west-2
```

## Quick start

```bash
# Check local tools and AWS credentials.
make check

# Review the pinned values, then provision AWS infrastructure.
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cd terraform
terraform init
terraform apply
cd ..

# Configure kubectl and install the fixed device-plugin chart.
make kubeconfig
make device-plugin

# Optional, but useful when Hugging Face rate limits are a concern.
export HF_TOKEN=hf_xxx
make hf-secret

# Deploy and wait for the image pull, model download, and engine startup.
make deploy
make wait

# Confirm the running pod matches every locked runtime value.
make verify-runtime
```

Keep the port forward running in one terminal:

```bash
make port-forward
```

Then run the smoke tests or a controlled continuous-batching benchmark from a
second terminal:

```bash
make invoke-text
make invoke-image IMAGE_URL=https://raw.githubusercontent.com/pytorch/hub/master/images/dog.jpg
make invoke-video VIDEO_URL=https://example.com/clip.mp4

# Sends 4 warmup requests, then 40 measured requests while maintaining c4.
make load-test

# Throughput-oriented profile. Expect a larger P95 latency.
make load-test LOAD_CONCURRENCY=8
```

`scripts/12-load-test.py` reports the exact payload SHA-256, successful and
failed requests, wall-clock throughput, mean, P50, P95, and maximum latency.
P95 is calculated by linear interpolation over the inclusive ordered sample.
Supply the same request payload used by an evaluation pipeline to measure that
pipeline's serving behavior:

```bash
make load-test LOAD_PAYLOAD=/absolute/path/to/request.json
```

## Runtime verification

`make verify-runtime` checks the Deployment image digest, the image digest
actually running in the pod, model revision in the Hugging Face cache, vLLM
arguments, DeepGEMM setting, one allocatable GPU, and `/v1/models`. It exits
nonzero on any mismatch and writes a compact JSON record on success.

The command deliberately does not claim model-quality equivalence. The
evaluation repository owns prompts, frames, labels, metrics, and results; this
repository owns the server environment that handles those requests.

## Why vLLM instead of NIM

The original design used `nvcr.io/nim/nvidia/cosmos3-reasoner`. NIM images
require an NGC entitlement. This PoC instead serves the open Hugging Face
checkpoint with vLLM, so no NGC dependency is required.

The plain `vllm/vllm-openai` image does not support Cosmos3. The pinned
`vllm/vllm-omni` image includes the required `vllm-cosmos3` plugin.

## Cost and teardown

Costs include the EKS control plane, NAT gateway, g6e GPU node, EBS root
volumes, and data transfer. Delete both Kubernetes and AWS resources when the
test is complete:

```bash
make clean-k8s
cd terraform
terraform destroy
```

## Documents

- [Architecture and server decisions](docs/DESIGN.md)
- [Operational troubleshooting](docs/TROUBLESHOOTING.md)
- [Primary external references](docs/LINKS.md)

## License

This sample repository is provided as-is. `nvidia/Cosmos3-Nano` is distributed
under NVIDIA OpenMDW 1.1. Review the model license before use.
