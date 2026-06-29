# ============================================
# modules/security/variables.tf
# ============================================

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the security group will be created"
  type        = string
}

variable "ssh_allowed_ip" {
  description = "Your public IP for SSH access (with /32 CIDR)"
  type        = string
}