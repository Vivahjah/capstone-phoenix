# ============================================
# modules/security/main.tf - CORRECTED
# ONLY define security group here
# ============================================

resource "aws_security_group" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for Phoenix cluster"
  vpc_id      = var.vpc_id

  # SSH - only from your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_ip]
    description = "SSH from allowed IP"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Kubernetes API - INTERNAL ONLY (Security requirement!)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Only internal network
    description = "Kubernetes API - internal only"
  }

  # Node-to-node communication - INTERNAL ONLY
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Only internal network
    description = "Node-to-node communication"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# ===== OUTPUT =====
output "security_group_id" {
  value = aws_security_group.main.id
}