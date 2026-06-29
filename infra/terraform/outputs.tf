# ============================================
# outputs.tf - Root Module Outputs
# ============================================

# Control Plane
output "control_plane_public_ip" {
  value       = module.compute.control_plane_public_ip
  description = "Public IP of the control plane"
}

output "control_plane_private_ip" {
  value       = module.compute.control_plane_private_ip
  description = "Private IP of the control plane"
}

# Workers
output "worker_public_ips" {
  value       = module.compute.worker_public_ips
  description = "Public IPs of worker nodes"
}

output "worker_private_ips" {
  value       = module.compute.worker_private_ips
  description = "Private IPs of worker nodes"
}

# All IPs
output "all_public_ips" {
  value       = module.compute.all_public_ips
  description = "All public IPs in the cluster"
}

output "all_private_ips" {
  value       = module.compute.all_private_ips
  description = "All private IPs in the cluster"
}

# Convenience outputs
output "ssh_control_plane" {
  value       = module.compute.ssh_control_plane
  description = "SSH command for control plane"
}

output "ssh_workers" {
  value       = module.compute.ssh_workers
  description = "SSH commands for workers"
}

output "k3s_server_url" {
  value       = module.compute.k3s_server_url
  description = "K3s server URL for workers to join"
}

output "k3s_get_token" {
  value       = module.compute.k3s_token_command
  description = "Command to get K3s token"
}