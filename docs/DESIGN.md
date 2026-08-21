# Design

## Goal

This repository creates a reproducible single-GPU server for
`nvidia/Cosmos3-Nano`. It owns AWS infrastructure and serving behavior. The
separate evaluation repository owns input sampling, prompts, labels, metrics,
and reported model quality.

The target is a repeatable PoC in `us-west-2`, not a production deployment.

## Architecture

```text
Developer laptop
  | terraform apply
  v
AWS account
  +-- VPC: 2 public and 2 private subnets, 1 NAT gateway
  +-- EKS 1.34 cluster
        +-- system node group: AL2023 standard, m7i.large
        +-- GPU node group: AL2023 NVIDIA, g6e.2xlarge, 1 L40S
              - taint: nvidia.com/gpu=true:NoSchedule
              - labels: workload=cosmos, accelerator=nvidia

Kubernetes
  +-- NVIDIA device plugin chart 0.20.0
  +-- namespace/cosmos
        +-- optional hf-token-secret
        +-- Deployment: one vLLM pod, one GPU
        +-- Service: ClusterIP port 8000

Local client
  +-- kubectl port-forward service/cosmos3-nano-vllm 8000:8000
  +-- OpenAI-compatible POST /v1/chat/completions
```

## Pinned inputs

Mutable tags and API-selected latest versions cannot reproduce a server. The
following inputs are fixed:

| Input | Value |
| --- | --- |
| vLLM image | `vllm/vllm-omni@sha256:970dee6658ea223f615b2438ce41e47f1d5322225482546e6e6bc5d8134f757c` |
| Image source tag when resolved | `vllm/vllm-omni:cosmos3`, Linux AMD64, resolved 2026-08-22 |
| Model checkpoint | `nvidia/Cosmos3-Nano@411f42a8fdfb8c5b2583cb8786e0938f49796eaa` |
| EKS version | 1.34 |
| System and NVIDIA AMI release | `1.34.9-20260818` |
| VPC CNI | `v1.22.4-eksbuild.3` |
| kube-proxy | `v1.34.6-eksbuild.18` |
| CoreDNS | `v1.12.4-eksbuild.18` |
| AWS provider | 5.100.0 |
| NVIDIA device-plugin chart | 0.20.0 |

Terraform stores the provider checksums for macOS ARM64 and Linux AMD64 in
`.terraform.lock.hcl`. The AMI and add-on values were resolved for `us-west-2`
on 2026-08-22. Update each fixed value deliberately and record both the source
date and validation result.

The vLLM image digest is the runtime boundary. Its metadata identifies vLLM
0.25.0 and build commit `dd10e03f95f94edbea1975c67ace3a35ec9a8a40`. Earlier
validation of the mutable `cosmos3` tag used a vLLM 0.21 image. Do not describe
the newer digest as GPU-validated until `make verify-runtime`, smoke tests, and
the target workload benchmark have completed on a deployed cluster.

## Serving command

The Deployment invokes:

```text
vllm serve nvidia/Cosmos3-Nano \
  --revision 411f42a8fdfb8c5b2583cb8786e0938f49796eaa \
  --host 0.0.0.0 \
  --port 8000 \
  --tensor-parallel-size 1 \
  --max-model-len 32768 \
  --allowed-local-media-path / \
  --media-io-kwargs '{"video": {"num_frames": -1}}'
```

`VLLM_USE_DEEP_GEMM=0` is set because the Cosmos serving stack can otherwise
fail to initialize when DeepGEMM is unavailable.

The model's default maximum sequence length is 262144. On an L40S, the model
weights leave about 21 GiB for the KV cache, while that default needs about
36 GiB. `--max-model-len 32768` fits the one-GPU target and is sufficient for
the requested video workloads.

The Deployment intentionally does not pass `--async-scheduling`,
`--enable-chunked-prefill`, or `--max-num-batched-tokens`. The fixed vLLM image
defines the scheduler defaults. Testing on a different image can change those
defaults, which is why the image itself is pinned.

## Continuous batching

vLLM's default scheduler continuously batches compatible active requests into
each GPU iteration. A single client request cannot exercise that capability.
The load generator keeps a fixed number of HTTP requests in flight, submitting
the next request immediately after a prior one completes.

The latency-oriented profile is c4:

| Profile | Client concurrency | Mean wall time per ROAD clip | P95 latency | GPU cost per 1,000 clips |
| --- | ---: | ---: | ---: | ---: |
| c4 | 4 | 1.38 s | 5.75 s | USD 0.862 |
| c8 | 8 | 1.22 s | 13.78 s | USD 0.759 |

The c4 profile is the default because c8 more than doubles the observed P95
latency for a modest throughput improvement. It is not a server command-line
option. Reproduce it by keeping four requests in flight:

```bash
make port-forward
make load-test LOAD_PAYLOAD=/absolute/path/to/evaluation-request.json
```

The generator sends four warmup requests by default, then 40 measured requests.
It reports a SHA-256 hash of the canonical request JSON, request count,
concurrency, throughput, and latency statistics. P95 uses linear interpolation
over the inclusive ordered sample at p=0.95. Keep the request payload, request
count, concurrency, hardware, and runtime lock values unchanged when comparing
runs.

The values above come from the ROAD evaluation setup. They are a selection
baseline for c4 versus c8, not a promise for a different video, prompt,
network path, or container image.

## Runtime verification

`scripts/11-verify-runtime.sh` checks the live Deployment and ready pod:

- configured and running image digest
- model revision in the Hugging Face cache
- tensor parallel size, maximum model length, media I/O settings, and absence of async scheduling
- `VLLM_USE_DEEP_GEMM=0`
- exactly one allocatable GPU on the Cosmos node
- `nvidia/Cosmos3-Nano` returned from `/v1/models`

Run it after every deployment and before a benchmark:

```bash
make verify-runtime
```

It verifies configuration identity, not output equivalence or quality metrics.

## Infrastructure boundaries

Terraform owns the VPC, NAT gateway, EKS cluster, node groups, IAM resources,
and EKS core add-ons. Kubernetes manifests and scripts own the device plugin,
Hugging Face token secret, and server workload. Keeping `HF_TOKEN` outside
Terraform prevents it from entering Terraform state.

The HF cache is an `emptyDir` to keep the PoC simple. Deleting or replacing the
pod triggers another model download. A production system should use a
persistent cache, an ECR image mirror, authentication, rate limiting,
observability, autoscaling, a secure ingress, and a multi-replica rollout
strategy.

## First-start behavior

The image is large, the model download is about 28 GB, and engine initialization
can take many minutes. The startup probe permits about 60 minutes before
Kubernetes restarts the container. Readiness and liveness probes are disabled
until that startup probe succeeds.

## Historical decisions

The server runs on EKS rather than SageMaker because the EC2 g6e quota could be
provisioned for the original test while the SageMaker endpoint quota was not
available. It uses vLLM rather than NVIDIA NIM because the NGC organization
used for the test had no NIM entitlement. The pinned omni image supplies the
Cosmos3 architecture support that the plain `vllm/vllm-openai` image lacks.
