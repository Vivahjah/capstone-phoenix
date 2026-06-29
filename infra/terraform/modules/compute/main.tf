# ============================================
# modules/compute/main.tf - Fixed IP Assignment
# ============================================

# ===== CONTROL PLANE =====
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [var.security_group_id]

  # Use first subnet (10.0.0.0/24)
  private_ip = "10.0.0.10"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name      = "${var.project_name}-control-plane"
    Project   = var.project_name
    Role      = "control-plane"
  }
}

# ===== WORKER NODES =====
resource "aws_instance" "workers" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_ids[count.index]
  vpc_security_group_ids = [var.security_group_id]

  # Dynamic IP based on subnet
  private_ip = count.index == 0 ? "10.0.0.20" : "10.0.1.20"

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name      = "${var.project_name}-worker-${count.index + 1}"
    Project   = var.project_name
    Role      = "worker"
  }
}

# ===== OUTPUTS =====
# Control Plane Outputs
output "control_plane_public_ip" {
  value = aws_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.control_plane.private_ip
}

# Worker Outputs
output "worker_public_ips" {
  value = aws_instance.workers[*].public_ip
}

output "worker_private_ips" {
  value = aws_instance.workers[*].private_ip
}

# Combined Outputs
output "all_public_ips" {
  value = concat(
    [aws_instance.control_plane.public_ip],
    aws_instance.workers[*].public_ip
  )
}

output "all_private_ips" {
  value = concat(
    [aws_instance.control_plane.private_ip],
    aws_instance.workers[*].private_ip
  )
}

# SSH Commands
output "ssh_control_plane" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.control_plane.public_ip}"
}

output "ssh_workers" {
  value = [
    for i, ip in aws_instance.workers[*].public_ip : 
    "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}"
  ]
}

# K3s specific
output "k3s_server_url" {
  value = "https://${aws_instance.control_plane.private_ip}:6443"
}

output "k3s_token_command" {
  value = "sudo cat /var/lib/rancher/k3s/server/node-token"
}