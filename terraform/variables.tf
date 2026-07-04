variable "aws_region" {
  description = "AWS region to deploy the PoC."
  type        = string
  default     = "us-east-1"
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
