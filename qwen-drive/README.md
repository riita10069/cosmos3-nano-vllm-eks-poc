# Qwen-Drive-1.0-4B on the cosmos3-vllm-poc EKS cluster

Serves the VLM of `Qwen/Qwen-Drive-1.0-4B` (revision `28484089`) with upstream
vLLM for the ROAD scene-labeling comparison against Cosmos 3. The benchmark
code and report are in `riita10069/cosmos3-reasoner-nim-endpoint-terraform`
(`qwen-drive-extension/`).

## Files

- `qwen-drive-vllm.yaml`: Deployment and ClusterIP Service in namespace `cosmos`
- `convert_qwen_drive.py`: init-container script. Downloads the checkpoint,
  strips the `vlm.` prefix from the 723 VLM tensors (bytes unchanged) and writes
  a plain `Qwen3_5ForConditionalGeneration` checkpoint to
  `/var/lib/qwen-drive/models` on the node. The planning expert and BEV
  perception head are not used.

## Node group

g6e/g6 were out of capacity in all us-west-2 AZs on 2026-10-19, so the run used
a separate managed node group created with the AWS CLI (not Terraform):

```bash
aws eks create-nodegroup --cluster-name cosmos3-vllm-poc --region us-west-2 \
  --nodegroup-name gpu-qwen-drive-l4 \
  --node-role arn:aws:iam::<account>:role/cosmos3-vllm-poc-node-role \
  --subnets <private-subnet-2a> <private-subnet-2b> \
  --ami-type AL2023_x86_64_NVIDIA --release-version 1.34.9-20260625 \
  --capacity-type ON_DEMAND --instance-types g6.2xlarge g6.4xlarge g5.2xlarge \
  --disk-size 500 --scaling-config minSize=0,maxSize=1,desiredSize=1 \
  --labels accelerator=nvidia,workload=cosmos,nodepool=gpu-qwen-drive-l4 \
  --taints key=nvidia.com/gpu,value=true,effect=NO_SCHEDULE
```

The evaluation ran on g5.2xlarge (A10G 24GB).

## Deploy

```bash
kubectl -n cosmos create configmap qwen-drive-convert \
  --from-file=convert_qwen_drive.py=qwen-drive/convert_qwen_drive.py
kubectl apply -f qwen-drive/qwen-drive-vllm.yaml
kubectl -n cosmos port-forward svc/qwen-drive-vllm 18003:8000
```

## Notes

- Use `vllm/vllm-openai:v0.32.0` (CUDA 13). The `-cu129` variant fails to start
  because its torchcodec links `libnvrtc.so.13`. The AL2023 NVIDIA AMI ships
  driver 580 (CUDA 13.0).
- vLLM 0.32 resamples fully decoded videos to 2 fps for Qwen3-VL-family models;
  per-request `mm_processor_kwargs` and an `fps` entry in the video
  preprocessor config had no effect. Encode benchmark frames at 2 fps to keep
  all of them.
- `--max-num-batched-tokens 16384` raises the encoder cache above the default
  12,288 tokens; videos with an odd frame count (21/23) reach 12.4k-13.2k
  embedding tokens and are otherwise rejected mid-stream.
- `--trust-request-mm-kwargs` is required because the benchmark client sends
  `media_io_kwargs` per request. The endpoint is only reachable via port-forward.
- Prefix caching runs in mamba `align` mode and showed a 0% hit rate.
