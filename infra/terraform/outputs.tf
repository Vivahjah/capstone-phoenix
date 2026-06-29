output "control_plane_public_ip" {
  value = module.compute.control_plane_public_ip
}

output "worker_public_ips" {
  value = module.compute.worker_public_ips
}

output "control_plane_private_ip" {
  value = module.compute.control_plane_private_ip
}

output "all_public_ips" {
  value = concat(
    [module.compute.control_plane_public_ip],
    module.compute.worker_public_ips
  )
}