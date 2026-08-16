

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "Your current public IP in CIDR form (e.g. 102.89.23.163/32). Update this every session before apply — see docs/RUNBOOK.md."
  type        = string
}

variable "project_name" {
  description = "Prefix used for naming all resources (VPC, SG, instances, key pair)"
  type        = string
  default     = "capstone-phoenix"
}


variable "ssh_public_key_path" {
  description = "Path to the local SSH public key file used to create the AWS key pair"
  type        = string
}

variable "server_instance_type" {
  description = "Instance type for the k3s control-plane node"
  type        = string
  default     = "t3.small"
}

variable "worker_instance_type" {
  description = "Instance type for the k3s worker nodes"
  type        = string
  default     = "t3.small"
}
