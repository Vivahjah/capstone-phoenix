variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ssh_allowed_ip" {
  description = "Your public IP for SSH access"
  type        = string
}

variable "key_name" {
  description = "Name of AWS key pair"
  type        = string
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "capstone-phoenix"
}