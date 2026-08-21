variable "aws_region" {
  description = "AWS region to deploy the PoC."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix used for all resources."
  type        = string
  default     = "cosmos3-vllm-poc"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the PoC VPC."
  type        = string
  default     = "10.90.0.0/16"
}

variable "availability_zones" {
  description = "Exactly two availability zones used by the VPC and EKS node groups."
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly two zones."
  }
}

variable "gpu_instance_type" {
  description = "GPU instance type for Cosmos3-Nano vLLM."
  type        = string
  default     = "g6e.2xlarge"
}

variable "system_instance_type" {
  description = "Instance type for the system node group."
  type        = string
  default     = "m7i.large"
}

variable "system_ami_release_version" {
  description = "Pinned EKS AL2023 standard AMI release for Kubernetes 1.34."
  type        = string
  default     = "1.34.9-20260818"
}

variable "gpu_ami_release_version" {
  description = "Pinned EKS AL2023 NVIDIA AMI release for Kubernetes 1.34."
  type        = string
  default     = "1.34.9-20260818"
}

variable "vpc_cni_addon_version" {
  description = "Pinned EKS VPC CNI add-on version for Kubernetes 1.34."
  type        = string
  default     = "v1.22.4-eksbuild.3"
}

variable "kube_proxy_addon_version" {
  description = "Pinned EKS kube-proxy add-on version for Kubernetes 1.34."
  type        = string
  default     = "v1.34.6-eksbuild.18"
}

variable "coredns_addon_version" {
  description = "Pinned EKS CoreDNS add-on version for Kubernetes 1.34."
  type        = string
  default     = "v1.12.4-eksbuild.18"
}

variable "gpu_node_disk_size" {
  description = "Root disk size in GiB for GPU nodes. Large disk is needed for Docker layers and Hugging Face cache."
  type        = number
  default     = 500
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default = {
    Project = "cosmos3-nano-vllm-eks-poc"
  }
}
