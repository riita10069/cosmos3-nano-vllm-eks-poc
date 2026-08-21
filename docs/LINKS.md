# LINKS

Primary references used by this PoC.

## Cosmos3 / model
- Hugging Face model: https://huggingface.co/nvidia/Cosmos3-Nano
- NVIDIA Cosmos repository: https://github.com/NVIDIA/Cosmos
- Cosmos cookbook: https://nvidia-cosmos.github.io/cosmos-cookbook/
- Develop Physical AI with NVIDIA Cosmos 3 (blog):
  https://developer.nvidia.com/blog/develop-physical-ai-reasoning-world-and-action-models-with-nvidia-cosmos-3

## vLLM
- OpenAI-compatible server: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html
- Docker deployment: https://docs.vllm.ai/en/latest/deployment/docker.html
- Docker Hub image source used by this sample (the manifest pins its Linux
  AMD64 digest rather than this mutable `cosmos3` tag):
  https://hub.docker.com/r/vllm/vllm-omni/tags
- vLLM architecture and scheduler design:
  https://docs.vllm.ai/en/latest/design/arch_overview/

## Amazon EKS + GPU
- Manage NVIDIA GPUs on EKS:
  https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html
- EKS accelerated AMIs (AL2023 NVIDIA):
  https://docs.aws.amazon.com/eks/latest/userguide/gpu-ami.html
- NVIDIA k8s device plugin: https://github.com/NVIDIA/k8s-device-plugin
- EC2 G6e instances: https://aws.amazon.com/ec2/instance-types/g6e/

## Terraform
- AWS provider (aws_eks_cluster / aws_eks_node_group / aws_eks_addon):
  https://registry.terraform.io/providers/hashicorp/aws/latest/docs
