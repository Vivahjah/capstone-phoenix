variable "project_name" {
  description = "Prefix used for naming the security group"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC this security group belongs to (from the network module)"
  type        = string
}

variable "my_ip" {
  description = "Your current public IP in CIDR form, e.g. 102.89.23.163/32 — restricts SSH and k3s API access"
  type        = string
}
