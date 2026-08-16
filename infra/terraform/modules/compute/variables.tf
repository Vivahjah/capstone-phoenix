variable "project_name" {
  description = "Prefix used for naming compute resources"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to launch instances into (from the network module)"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group to attach to instances (from the security module)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key file used to create the AWS key pair"
  type        = string
}

variable "server_instance_type" {
  description = "Instance type for the k3s control-plane node"
  type        = string
}

variable "worker_instance_type" {
  description = "Instance type for the k3s worker nodes"
  type        = string
}
